/**
Copyright: Copyright (c) 2013-2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.client.chunkman;

import std.concurrency : Tid, thisTid, send, receiveTimeout;
import std.datetime : msecs;
import std.stdio : writef, writeln, writefln;
import core.thread : thread_joinAll;

import dlib.math.vector : vec3, ivec3;

import voxelman.block;
import voxelman.blockman;
import voxelman.chunk;
import voxelman.chunkmesh;
import voxelman.config;
import voxelman.meshgen;
import voxelman.utils.workergroup;


///
struct ChunkMan
{
	Chunk*[ivec3] chunks;

	Chunk* chunksToRemoveQueue; // head of slist. Follow 'next' pointer in chunk
	size_t numChunksToRemove;
	
	// Stats
	size_t numMeshChunkTasks;
	size_t totalLoadedChunks;

	ChunkRange visibleRegion;
	ivec3 observerPosition = ivec3(int.max, int.max, int.max);
	uint viewRadius = VIEW_RADIUS;
	
	BlockMan blockMan;

	WorkerGroup!(meshWorkerThread) meshWorkers;

	void init()
	{
		blockMan.loadBlockTypes();

		meshWorkers.startWorkers(NUM_WORKERS, thisTid, blockMan.blocks);
	}

	void stop()
	{
		writefln("unloading chunks");

		foreach(chunk; chunks.byValue)
			addToRemoveQueue(chunk);

		while(chunks.length > 0)
		{
			update();
		}

		meshWorkers.stopWorkers();

		thread_joinAll();
	}

	void update()
	{
		bool message = true;
		while (message)
		{
			message = receiveTimeout(0.msecs,
				(immutable(MeshGenResult)* data){onMeshLoaded(cast(MeshGenResult*)data);}
				);
		}

		updateChunks();
	}

	void onChunkLoaded(ivec3 chunkPos, ChunkData chunkData)
	{
		//writefln("Chunk data received in main thread");

		Chunk* chunk = getChunk(chunkPos);
		assert(chunk !is null);

		chunk.hasWriter = false;
		chunk.isLoaded = true;

		assert(!chunk.isUsed);

		++totalLoadedChunks;

		chunk.isVisible = true;
		if (chunkData.uniform)
		{
			chunk.isVisible = blockMan.blocks[chunkData.uniformType].isVisible;
		}
		chunk.data = chunkData;

		if (chunk.isMarkedForDeletion)
		{
			delete chunkData.typeData;
			return;
		}

		if (chunk.isVisible)
			tryMeshChunk(chunk);
		foreach(a; chunk.adjacent)
			if (a !is null) tryMeshChunk(a);
	}

	void tryMeshChunk(Chunk* chunk)
	{
		if (chunk.needsMesh && chunk.canBeMeshed)
		{
			++chunk.numReaders;
			foreach(a; chunk.adjacent)
				if (a !is null) ++a.numReaders;

			chunk.isMeshing = true;
			++numMeshChunkTasks;
			meshWorkers.nextWorker.send(cast(shared(Chunk)*)chunk);
		}
	}

	void onMeshLoaded(MeshGenResult* data)
	{
		Chunk* chunk = getChunk(data.coord);

		assert(chunk !is null);

		chunk.isMeshing = false;

		// Allow chunk to be written or deleted.
		--chunk.numReaders;
		foreach(a; chunk.adjacent)
				if (a !is null) --a.numReaders;
		--numMeshChunkTasks;

		// Chunk is already in delete queue
		if (!visibleRegion.contains(data.coord))
		{
			delete data.meshData;
			delete data;
			return;
		}

		// Attach mesh
		if (chunk.mesh is null) chunk.mesh = new ChunkMesh();
		chunk.mesh.data = data.meshData;
		
		ivec3 coord = chunk.coord;
		chunk.mesh.position = vec3(coord.x, coord.y, coord.z) * CHUNK_SIZE - 0.5f;
		chunk.mesh.isDataDirty = true;
		chunk.isVisible = chunk.mesh.data.length > 0;
		chunk.hasMesh = true;

		//writefln("Chunk mesh generated at %s", chunk.coord);
	}

	void printList(Chunk* head)
	{
		while(head)
		{
			writef("%s ", head);
			head = head.next;
		}
		writeln;
	}

	void printAdjacent(Chunk* chunk)
	{
		void printChunk(Side side)
		{
			byte[3] offset = sideOffsets[side];
			ivec3 otherCoord = ivec3(chunk.coord.x + offset[0],
									chunk.coord.y + offset[1],
									chunk.coord.z + offset[2]);
			Chunk* c = getChunk(otherCoord);
			writef("%s", c is null ? "null" : "a");
		}

		foreach(s; Side.min..Side.max)
			printChunk(s);
		writeln;
	}

	void updateChunks()
	{
		processRemoveQueue();
	}

	void processRemoveQueue()
	{
		Chunk* chunk = chunksToRemoveQueue;

		while(chunk)
		{
			assert(chunk !is null);
			//printList(chunk);

			if (!chunk.isUsed)
			{
				auto toRemove = chunk;
				chunk = chunk.next;

				removeFromRemoveQueue(toRemove);
				removeChunk(toRemove);
			}
			else
			{
				auto c = chunk;
				chunk = chunk.next;
			}
		}
	}

	Chunk* createEmptyChunk(ivec3 coord)
	{
		return new Chunk(coord);
	}

	Chunk* getChunk(ivec3 coord)
	{
		return chunks.get(coord, null);
	}

	@property auto visibleChunks()
	{
		import std.algorithm : filter;
		return chunks
			.byValue
			.filter!((c) => c.isLoaded && c.isVisible && c.hasMesh && c.mesh !is null);
	}

	ChunkRange calcChunkRange(ivec3 coord)
	{
		auto size = viewRadius*2 + 1;
		return ChunkRange(cast(ivec3)(coord - viewRadius),
			ivec3(size, size, size));
	}

	void updateObserverPosition(vec3 cameraPos)
	{
		import std.conv : to;

		ivec3 chunkPos = ivec3(
			to!int(cameraPos.x) / CHUNK_SIZE,
			to!int(cameraPos.y) / CHUNK_SIZE,
			to!int(cameraPos.z) / CHUNK_SIZE);

		if (chunkPos == observerPosition) return;
		observerPosition = chunkPos;
		
		ChunkRange newRegion = calcChunkRange(chunkPos);
		
		updateVisibleRegion(newRegion);
	}

	void updateVisibleRegion(ChunkRange newRegion)
	{
		auto oldRegion = visibleRegion;
		visibleRegion = newRegion;

		bool cond = oldRegion.size.x == 0 &&
			oldRegion.size.y == 0 &&
			oldRegion.size.z == 0;

		if (cond)
		{
			loadRegion(newRegion);
			return;
		}

		auto chunksToRemove = oldRegion.chunksNotIn(newRegion);

		// remove chunks
		foreach(chunkCoord; chunksToRemove)
		{
			addToRemoveQueue(getChunk(chunkCoord));
		}

		// load chunks
		// ivec3[] chunksToLoad = newRegion.chunksNotIn(oldRegion).array;
		// sort!((a, b) => a.euclidDist(observerPosition) > b.euclidDist(observerPosition))(chunksToLoad);
		foreach(chunkCoord; newRegion.chunksNotIn(oldRegion))
		{
			loadChunk(chunkCoord);
		}
	}

	void loadChunk(ivec3 coord)
	{
		if (auto chunk = coord in chunks) 
		{
			if ((*chunk).isMarkedForDeletion)
				removeFromRemoveQueue(*chunk);
			return;
		}
		Chunk* chunk = createEmptyChunk(coord);
		addChunk(chunk);
	}

	void loadRegion(ChunkRange region)
	{
		foreach(int x; region.coord.x..(region.coord.x + region.size.x))
		foreach(int y; region.coord.y..(region.coord.y + region.size.y))
		foreach(int z; region.coord.z..(region.coord.z + region.size.z))
		{
			loadChunk(ivec3(x, y, z));
		}
	}

	// Add already created chunk to storage
	// Sets up all adjacent
	void addChunk(Chunk* emptyChunk)
	{
		assert(emptyChunk);
		chunks[emptyChunk.coord] = emptyChunk;
		ivec3 coord = emptyChunk.coord;

		void attachAdjacent(ubyte side)()
		{
			byte[3] offset = sideOffsets[side];
			ivec3 otherCoord = ivec3(cast(int)(coord.x + offset[0]),
												cast(int)(coord.y + offset[1]),
												cast(int)(coord.z + offset[2]));
			Chunk* other = getChunk(otherCoord);

			if (other !is null) 
				other.adjacent[oppSide[side]] = emptyChunk;
			emptyChunk.adjacent[side] = other;
		}

		// Attach all adjacent
		attachAdjacent!(0)();
		attachAdjacent!(1)();
		attachAdjacent!(2)();
		attachAdjacent!(3)();
		attachAdjacent!(4)();
		attachAdjacent!(5)();
	}

	void addToRemoveQueue(Chunk* chunk)
	{
		assert(chunk);
		assert(chunk !is null);

		// already queued
		if (chunk.next != null && chunk.prev != null) return;
		
		chunk.next = chunksToRemoveQueue;
		if (chunksToRemoveQueue) chunksToRemoveQueue.prev = chunk;
		chunksToRemoveQueue = chunk;
		++numChunksToRemove;
	}

	void removeFromRemoveQueue(Chunk* chunk)
	{
		assert(chunk);
		assert(chunk !is null);

		if (chunk.prev)
			chunk.prev.next = chunk.next;
		else
			chunksToRemoveQueue = chunk.next;

		if (chunk.next)
			chunk.next.prev = chunk.prev;

		chunk.next = null;
		chunk.prev = null;
		--numChunksToRemove;
	}

	void removeChunk(Chunk* chunk)
	{
		assert(chunk);
		assert(chunk !is null);

		assert(!chunk.isUsed);

		void detachAdjacent(ubyte side)()
		{
			if (chunk.adjacent[side] !is null)
			{
				chunk.adjacent[side].adjacent[oppSide[side]] = null;
			}
			chunk.adjacent[side] = null;
		}

		// Detach all adjacent
		detachAdjacent!(0)();
		detachAdjacent!(1)();
		detachAdjacent!(2)();
		detachAdjacent!(3)();
		detachAdjacent!(4)();
		detachAdjacent!(5)();

		chunks.remove(chunk.coord);
		if (chunk.mesh)
			chunk.mesh.free();
		delete chunk.mesh;
		delete chunk;
	}
}