/**
Copyright: Copyright (c) 2013-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.client.chunkman;

//import std.concurrency : Tid, thisTid, send, receiveTimeout;
import std.stdio : writef, writeln, writefln;

import dlib.math.vector : vec3, ivec3;

import voxelman.block;
import voxelman.blockman;
import voxelman.chunk;
import voxelman.config;
import voxelman.client.chunkmeshman;


///
struct ChunkMan
{
	Chunk*[ivec3] chunks;

	Chunk* chunksToRemoveQueue; // head of slist. Follow 'next' pointer in chunk
	size_t numChunksToRemove;

	// Stats
	size_t totalLoadedChunks;

	ChunkRange visibleRegion;
	ivec3 observerPosition = ivec3(int.max, int.max, int.max);
	uint viewRadius = VIEW_RADIUS;

	BlockMan blockMan;
	ChunkMeshMan chunkMeshMan;

	void init()
	{
		blockMan.loadBlockTypes();
		chunkMeshMan.init(&this, &blockMan);
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

		chunkMeshMan.stop();
	}

	void update()
	{
		chunkMeshMan.update();
		processRemoveQueue();
	}

	void onChunkLoaded(ivec3 chunkPos, ChunkData chunkData)
	{
		Chunk* chunk = getChunk(chunkPos);

		// We can receive data for chunk that is already deleted.
		if (chunk is null || chunk.isMarkedForDeletion)
		{
			chunkData.deleteTypeData();
			return;
		}

		chunkMeshMan.onChunkLoaded(chunk, chunkData);
	}

	void onChunkChanged(ivec3 chunkPos, BlockChange[] changes)
	{
		Chunk* chunk = getChunk(chunkPos);

		// We can receive data for chunk that is already deleted.
		if (chunk is null || chunk.isMarkedForDeletion)
			return;

		chunkMeshMan.onChunkChanged(chunk, changes);
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
		assert(chunk);
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
		ivec3 chunkPos = cameraToChunkPos(cameraPos);

		if (chunkPos == observerPosition) return;
		observerPosition = chunkPos;

		ChunkRange newRegion = calcChunkRange(chunkPos);

		updateVisibleRegion(newRegion);
	}

	void updateVisibleRegion(ChunkRange newRegion)
	{
		auto oldRegion = visibleRegion;
		visibleRegion = newRegion;

		if (oldRegion.empty)
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
		chunkMeshMan.onChunkRemoved(chunk);

		if (chunk.mesh)
			chunk.mesh.free();
		delete chunk.mesh;
		delete chunk;
	}
}
