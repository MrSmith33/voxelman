/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.storage.chunkprovider;

import core.thread : thread_joinAll;
import std.concurrency : Tid, thisTid, send, receiveTimeout;
import std.datetime : msecs;
import std.experimental.logger;

import dlib.math.vector;

import voxelman.config;
import voxelman.chunkgen;
import voxelman.storage.chunk;
import voxelman.storage.chunkstorage;
import voxelman.storage.storageworker;
import voxelman.storage.world;
import voxelman.utils.queue : Queue;
import voxelman.utils.workergroup;

version = Disk_Storage;

struct ChunkProvider
{
private:
	WorkerGroup!(chunkGenWorkerThread) genWorkers;
	WorkerGroup!(storageWorkerThread) storeWorker;
	Queue!ivec3 loadQueue;
	ChunkStorage* chunkStorage;

	size_t chunksEnqueued;
	size_t maxChunksToEnqueue = 400;
	size_t numLoadChunkTasks;
	size_t totalLoadedChunks;

public:
	void delegate(Chunk* chunk)[] onChunkLoadedHandlers;

	void init(string worldDir, ChunkStorage* chunkStorage)
	{
		assert(chunkStorage);
		this.chunkStorage = chunkStorage;

		genWorkers.startWorkers(NUM_WORKERS, thisTid);
		version(Disk_Storage)
			storeWorker.startWorkers(1, thisTid, worldDir);
	}

	void stop()
	{
		infof("saving chunks %s", chunkStorage.chunks.length);

		foreach(chunk; chunkStorage.chunks.byValue)
			chunkStorage.removeQueue.add(chunk);

		size_t toBeDone = chunkStorage.chunks.length;
		uint donePercentsPrev;

		while(chunkStorage.chunks.length > 0)
		{
			update();
			chunkStorage.update();

			auto donePercents = cast(float)(toBeDone - chunkStorage.chunks.length) / toBeDone * 100;
			if (donePercents >= donePercentsPrev + 10)
			{
				donePercentsPrev += ((donePercents - donePercentsPrev) / 10) * 10;
				infof("saved %s%%", donePercentsPrev);
			}
		}

		genWorkers.stopWorkers();

		version(Disk_Storage)
			storeWorker.stopWorkersWhenDone();

		thread_joinAll();
	}

	void update()
	{
		bool message = true;
		while (message)
		{
			message = receiveTimeout(0.msecs,
				(immutable(ChunkGenResult)* data){onChunkLoaded(cast(ChunkGenResult*)data);}
			);
		}
	}

	void onChunkAdded(Chunk* chunk)
	{
		chunk.hasWriter = true;
		++numLoadChunkTasks;

		version(Disk_Storage)
		{
			storeWorker.nextWorker.send(chunk.coord, genWorkers.nextWorker);
		}
		else
		{
			genWorkers.nextWorker.send(chunk.coord);
		}
	}

	void onChunkRemoved(Chunk* chunk)
	{
		//loadQueue.put(chunkCoord);

		version(Disk_Storage)
		{
			storeWorker.nextWorker.send(
				chunk.coord, cast(shared)chunk.snapshot.blockData,
				chunk.snapshot.timestamp, true);
		}
		else
		{
			delete chunk.snapshot.blockData.blocks;
		}
	}

	void onChunkLoaded(ChunkGenResult* data)
	{
		//writefln("Chunk data received in main thread");

		Chunk* chunk = chunkStorage.getChunk(data.coord);
		assert(chunk !is null);

		chunk.hasWriter = false;
		chunk.isLoaded = true;

		assert(!chunk.isUsed);

		++totalLoadedChunks;
		--numLoadChunkTasks;
		//--chunksEnqueued;

		chunk.isVisible = true;
		chunk.snapshot.blockData = data.blockData;
		chunk.snapshot.timestamp = data.timestamp;

		if (chunk.isMarkedForDeletion)
		{
			return;
		}

		foreach(handler; onChunkLoadedHandlers)
			handler(chunk);
	}
}
