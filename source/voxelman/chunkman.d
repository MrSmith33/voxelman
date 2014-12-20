/**
Copyright: Copyright (c) 2013-2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.chunkman;

import std.concurrency : Tid, thisTid, send, receiveTimeout;
import std.datetime : msecs;
import std.stdio : writef, writeln, writefln;
import core.thread : thread_joinAll;

import cbor;
import dlib.math.vector : vec3, ivec3;

import voxelman.block;
import voxelman.chunk;
import voxelman.chunkgen;
import voxelman.chunkmesh;
import voxelman.meshgen;
import voxelman.regionstorage;
import voxelman.rlecompression;
import voxelman.workergroup;

version = Disk_Storage;

enum string SAVE_DIR = "save";
enum NUM_WORKERS = 2;
enum VIEW_RADIUS = 8;
enum WORLD_SIZE = 12; // chunks
enum BOUND_WORLD = false;

private ubyte[4096*16] buffer;
private ubyte[4096*16] compressBuffer;

///
struct ChunkMan
{
	RegionStorage* regionStorage;
	Chunk*[ulong] chunks;

	Chunk* chunksToRemoveQueue; // head of slist. Follow 'next' pointer in chunk
	size_t numChunksToRemove;
	
	// Stats
	size_t numLoadChunkTasks;
	size_t numMeshChunkTasks;
	size_t totalLoadedChunks;

	ChunkRange visibleRegion;
	ChunkCoord observerPosition = ChunkCoord(short.max, short.max, short.max);
	uint viewRadius = VIEW_RADIUS;
	
	IBlock[] blockTypes;

	WorkerGroup!(chunkGenWorkerThread) genWorkers;
	WorkerGroup!(meshWorkerThread) meshWorkers;

	void init()
	{
		regionStorage = new RegionStorage(SAVE_DIR);
		loadBlockTypes();

		genWorkers.startWorkers(NUM_WORKERS, thisTid);
		meshWorkers.startWorkers(NUM_WORKERS, thisTid, cast(shared)&this);
	}

	void stop()
	{
		genWorkers.stopWorkers();
		meshWorkers.stopWorkers();

		regionStorage.clear();

		thread_joinAll();
	}

	void update()
	{
		//writefln("cm.update");
		//stdout.flush;
		bool message = true;
		while (message)
		{
			message = receiveTimeout(0.msecs,
				(immutable(ChunkGenResult)* data){onChunkLoaded(cast(ChunkGenResult*)data);},
				(immutable(MeshGenResult)* data){onMeshLoaded(cast(MeshGenResult*)data);}
				);
		}

		//writefln("cm.update 1");
		updateChunks();
		//writefln("cm.update end");
	}

	void onChunkLoaded(ChunkGenResult* data)
	{
		//writefln("Chunk data received in main thread");

		Chunk* chunk = getChunk(data.coord);
		assert(chunk != Chunk.unknownChunk);

		chunk.hasWriter = false;
		chunk.isLoaded = true;

		++totalLoadedChunks;
		--numLoadChunkTasks;

		if (chunk.isMarkedForDeletion)
		{
			delete data;
			return;
		}

		chunk.isVisible = true;
		if (data.chunkData.uniform)
		{
			chunk.isVisible = blockTypes[data.chunkData.uniformType].isVisible;
		}
		chunk.data = data.chunkData;

		if (chunk.isVisible)
			tryMeshChunk(chunk);
		foreach(a; chunk.adjacent)
			if (a != Chunk.unknownChunk) tryMeshChunk(a);
	}

	void tryMeshChunk(Chunk* chunk)
	{
		if (chunk.needsMesh && chunk.canBeMeshed)
		{
			++chunk.numReaders;
			foreach(a; chunk.adjacent)
				if (a != Chunk.unknownChunk) ++a.numReaders;

			chunk.isMeshing = true;
			++numMeshChunkTasks;
			meshWorkers.nextWorker.send(cast(shared(Chunk)*)chunk);
		}
	}

	void onMeshLoaded(MeshGenResult* data)
	{
		Chunk* chunk = getChunk(data.coord);

		assert(chunk != Chunk.unknownChunk);

		chunk.isMeshing = false;

		// Allow chunk to be written or deleted.
		--chunk.numReaders;
		foreach(a; chunk.adjacent)
				if (a != Chunk.unknownChunk) --a.numReaders;
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
		
		ChunkCoord coord = chunk.coord;
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
			ChunkCoord otherCoord = ChunkCoord(cast(short)(chunk.coord.x + offset[0]),
												cast(short)(chunk.coord.y + offset[1]),
												cast(short)(chunk.coord.z + offset[2]));
			Chunk* c = getChunk(otherCoord);
			writef("%s", c==Chunk.unknownChunk ? "unknownChunk" : "a");
		}

		foreach(s; Side.min..Side.max)
			printChunk(s);
		writeln;
	}

	void updateChunks()
	{
		// See if anything breaks
		assert(*Chunk.unknownChunk == *Chunk.initChunk);

		processRemoveQueue();
	}

	void processRemoveQueue()
	{
		Chunk* chunk = chunksToRemoveQueue;

		while(chunk)
		{
			assert(chunk != Chunk.unknownChunk);
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

	void loadBlockTypes()
	{
		blockTypes ~= new UnknownBlock(0);
		blockTypes ~= new AirBlock(1);
		blockTypes ~= new GrassBlock(2);
		blockTypes ~= new DirtBlock(3);
		blockTypes ~= new StoneBlock(4);
	}

	Chunk* createEmptyChunk(ChunkCoord coord)
	{
		return new Chunk(coord);
	}

	Chunk* getChunk(ChunkCoord coord)
	{
		Chunk** chunk = coord.asLong in chunks;
		if (chunk is null) return Chunk.unknownChunk;
		return *chunk;
	}

	@property auto visibleChunks()
	{
		import std.algorithm : filter;
		return chunks
		.byValue
		.filter!((c) => c.isLoaded && c.isVisible && c.hasMesh && c.mesh !is null);
	}

	ChunkRange calcChunkRange(ChunkCoord coord)
	{
		auto size = viewRadius*2 + 1;
		return ChunkRange(cast(ChunkCoord)(coord.vector - cast(short)viewRadius),
			ivec3(size, size, size));
	}

	void updateObserverPosition(vec3 cameraPos)
	{
		import std.conv : to;

		ChunkCoord chunkPos = ChunkCoord(
			to!short(to!int(cameraPos.x) / CHUNK_SIZE),
			to!short(to!int(cameraPos.y) / CHUNK_SIZE),
			to!short(to!int(cameraPos.z) / CHUNK_SIZE));

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
		// ChunkCoord[] chunksToLoad = newRegion.chunksNotIn(oldRegion).array;
		// sort!((a, b) => a.euclidDist(observerPosition) > b.euclidDist(observerPosition))(chunksToLoad);
		foreach(chunkCoord; newRegion.chunksNotIn(oldRegion))
		{
			loadChunk(chunkCoord);
		}
	}

	// Add already created chunk to storage
	// Sets up all adjacent
	void addChunk(Chunk* emptyChunk)
	{
		assert(emptyChunk);
		chunks[emptyChunk.coord.asLong] = emptyChunk;
		ChunkCoord coord = emptyChunk.coord;

		void attachAdjacent(ubyte side)()
		{
			byte[3] offset = sideOffsets[side];
			ChunkCoord otherCoord = ChunkCoord(cast(short)(coord.x + offset[0]),
												cast(short)(coord.y + offset[1]),
												cast(short)(coord.z + offset[2]));
			Chunk* other = getChunk(otherCoord);
			assert(other);

			if (other != Chunk.unknownChunk) 
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
		assert(chunk != Chunk.unknownChunk);
		//writefln("addToRemoveQueue %s pos %s", chunk.coord, observerPosition);
		//printAdjacent(chunk);
		
		chunk.next = chunksToRemoveQueue;
		if (chunksToRemoveQueue) chunksToRemoveQueue.prev = chunk;
		chunksToRemoveQueue = chunk;
		++numChunksToRemove;
	}

	void removeFromRemoveQueue(Chunk* chunk)
	{
		assert(chunk);
		assert(chunk != Chunk.unknownChunk);

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
		assert(chunk != Chunk.unknownChunk);

		assert(!chunk.isUsed);
		//assert(!chunk.isAnyAdjacentUsed);

		//writefln("remove chunk at %s", chunk.coord);

		void detachAdjacent(ubyte side)()
		{
			if (chunk.adjacent[side] != Chunk.unknownChunk)
			{
				chunk.adjacent[side].adjacent[oppSide[side]] = Chunk.unknownChunk;
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

		chunks.remove(chunk.coord.asLong);
		if (chunk.mesh) chunk.mesh.free();
		delete chunk.mesh;
		version(Disk_Storage)
		{
			if (isChunkInWorldBounds(chunk.coord))
				writeChunk(chunk.coord, chunk.data);
		}
		delete chunk.data.typeData;
		delete chunk;
	}

	void loadChunk(ChunkCoord coord)
	{
		if (auto chunk = coord.asLong in chunks) 
		{
			if ((*chunk).isMarkedForDeletion)
				removeFromRemoveQueue(*chunk);
			return;
		}
		Chunk* chunk = createEmptyChunk(coord);
		addChunk(chunk);

		if (!isChunkInWorldBounds(coord)) return;

		chunk.hasWriter = true;
		++numLoadChunkTasks;

		version(Disk_Storage)
		if (regionStorage.isChunkOnDisk(coord.asivec3))
		{
			try
			{
				ChunkData cd = readChunk(coord);
				ChunkGenResult* genResult = new ChunkGenResult(cd, coord);
				onChunkLoaded(genResult);
				return;
			}
			catch(Exception e)
			{
				writeln(e.msg);
			}
		}
		
		genWorkers.nextWorker.send(chunk.coord);
	}

	void writeChunk(ChunkCoord coord, ref ChunkData data)
	{
		//writef("writing chunk %s ", coord);
		ChunkData compressedData = data;
		compressedData.typeData = rleEncode(data.typeData, compressBuffer);
		try
		{
			size_t encodedSize = encodeCborArray(buffer[], compressedData);
			//writef("size %s compressed %s", data.typeData.length, compressedData.typeData.length);
			writeln;
			regionStorage.writeChunk(coord.asivec3, buffer[0..encodedSize]);
		}
		catch(Exception e)
		{
			//writefln("error %s", e);
		}
	}

	ChunkData readChunk(ChunkCoord coord)
	{
		assert(regionStorage.isChunkOnDisk(coord.asivec3));
		//writef("reading chunk %s ", coord);
		auto data = regionStorage.readChunk(coord.asivec3, buffer[]);
		ChunkData compressedData = decodeCborSingle!ChunkData(data);
		ChunkData uncompressedData = compressedData;
		uncompressedData.typeData = rleDecode(compressedData.typeData, compressBuffer).dup;

		//writefln("size %s compressed %s", uncompressedData.typeData.length, compressedData.typeData.length);

		return uncompressedData;
	}

	void loadRegion(ChunkRange region)
	{
		foreach(short x; region.coord.x..cast(short)(region.coord.x + region.size.x))
		foreach(short y; region.coord.y..cast(short)(region.coord.y + region.size.y))
		foreach(short z; region.coord.z..cast(short)(region.coord.z + region.size.z))
		{
			loadChunk(ChunkCoord(x, y, z));
		}
	}

	bool isChunkInWorldBounds(ChunkCoord coord)
	{
		static if (BOUND_WORLD)
		{
			if(coord.x<0 || coord.y<0 || coord.z<0 || coord.x>=WORLD_SIZE ||
				coord.y>=WORLD_SIZE || coord.z>=WORLD_SIZE)
				return false;
		}

		return true;
	}
}