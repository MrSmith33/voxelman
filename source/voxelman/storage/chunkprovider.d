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

import voxelman.chunkgen;
import voxelman.config;
import voxelman.storage.chunk;
import voxelman.storage.chunkstorage;
import voxelman.storage.coordinates;
import voxelman.storage.storageworker;
import voxelman.storage.world;
import voxelman.utils.workergroup;

version = Disk_Storage;

struct SnapshotLoadedMessage
{
	ChunkWorldPos cwp;
	BlockDataSnapshot snapshot;
}

struct SnapshotSavedMessage
{
	ChunkWorldPos cwp;
	BlockDataSnapshot snapshot;
}

struct LoadSnapshotMessage
{
	ChunkWorldPos cwp;
	BlockType[] blockBuffer;
	Tid genWorker;
}

struct SaveSnapshotMessage
{
	ChunkWorldPos cwp;
	BlockDataSnapshot snapshot;
}

struct ChunkProvider
{
private:
	WorkerGroup!(chunkGenWorkerThread) genWorkers;
	WorkerGroup!(storageWorkerThread) storeWorker;
	ChunkStorage* chunkStorage;

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
			storeWorker.startWorkers(1, thisTid, worldDir~"/regions");
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
				donePercentsPrev += cast(uint)((donePercents - donePercentsPrev) / 10) * 10;
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
				(immutable(SnapshotLoadedMessage)* message) {
					onChunkLoaded(cast(SnapshotLoadedMessage*)message);
				},
				(immutable(SnapshotSavedMessage)* message) {
					auto m = cast(SnapshotSavedMessage*)message;
					delete m.snapshot.blockData.blocks;
				}
			);
		}
	}

	void onChunkAdded(Chunk* chunk)
	{
		chunk.hasWriter = true;
		++numLoadChunkTasks;

		version(Disk_Storage)
		{
			auto buf = uninitializedArray!(BlockType[])(CHUNK_SIZE_CUBE);
			auto m = new LoadSnapshotMessage(chunk.position, buf, genWorkers.nextWorker);
			storeWorker.nextWorker.send(cast(immutable(LoadSnapshotMessage)*)m);
		}
		else
		{
			genWorkers.nextWorker.send(chunk.position);
		}
	}

	void onChunkRemoved(Chunk* chunk)
	{
		version(Disk_Storage)
		{
			auto m = new SaveSnapshotMessage(chunk.position, chunk.snapshot);
			storeWorker.nextWorker.send(cast(immutable(SaveSnapshotMessage)*)m);
		}
		else
		{
			delete chunk.snapshot.blockData.blocks;
		}
	}

	void onChunkLoaded(SnapshotLoadedMessage* data)
	{
		Chunk* chunk = chunkStorage.getChunk(data.cwp);
		assert(chunk !is null);

		chunk.hasWriter = false;
		chunk.isLoaded = true;

		assert(!chunk.isUsed);

		++totalLoadedChunks;
		--numLoadChunkTasks;

		chunk.isVisible = true;
		chunk.snapshot = data.snapshot;
		if (chunk.snapshot.blockData.uniform) {
			assert(chunk.snapshot.blockData.blocks.length == CHUNK_SIZE_CUBE);
			delete chunk.snapshot.blockData.blocks;
		}

		if (chunk.isMarkedForDeletion)
		{
			return;
		}

		foreach(handler; onChunkLoadedHandlers)
			handler(chunk);
	}
}
