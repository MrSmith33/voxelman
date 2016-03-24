/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.storage.chunkprovider;

import core.thread : thread_joinAll;
import std.concurrency : Tid, thisTid, send, receiveTimeout;
import std.datetime : msecs;
import std.experimental.logger;

import dlib.math.vector;

import voxelman.core.chunkgen;
import voxelman.core.config;
import voxelman.storage.chunk;
import voxelman.storage.chunkstorage;
import voxelman.storage.coordinates;
import voxelman.utils.workergroup;


struct SnapshotLoadedMessage
{
	ChunkWorldPos cwp;
	BlockDataSnapshot[] snapshots;
	bool saved;
}

struct SnapshotSavedMessage
{
	ChunkWorldPos cwp;
	BlockDataSnapshot[] snapshots;
}

struct LoadSnapshotMessage
{
	ChunkWorldPos cwp;
	Tid genWorker;
}

struct SaveSnapshotMessage
{
	ChunkWorldPos cwp;
	BlockDataSnapshot[] snapshots;
}

struct ChunkProvider
{
private:
	WorkerGroup!(chunkGenWorkerThread) genWorkers;
	Tid storeWorker;

public:
	void delegate(ChunkWorldPos, BlockDataSnapshot[], bool)[] onChunkLoadedHandlers;
	void delegate(ChunkWorldPos, BlockDataSnapshot[])[] onChunkSavedHandlers;
	size_t loadQueueLength;

	size_t loadQueueSpaceAvaliable() @property const
	{
		return MAX_LOAD_QUEUE_LENGTH - loadQueueLength;
	}

	void init(Tid storeWorker, uint numWorkers)
	{
		this.storeWorker = storeWorker;
		genWorkers.startWorkers(numWorkers, thisTid);
	}

	void stop()
	{
		genWorkers.stopWorkers();
	}

	void update()
	{
		bool message = true;
		while (message)
		{
			message = receiveTimeout(0.msecs,
				(immutable(SnapshotLoadedMessage)* message) {
					auto m = cast(SnapshotLoadedMessage*)message;
					--loadQueueLength;
					foreach(handler; onChunkLoadedHandlers)
						handler(m.cwp, m.snapshots, m.saved);
				},
				(immutable(SnapshotSavedMessage)* message) {
					auto m = cast(SnapshotSavedMessage*)message;
					foreach(handler; onChunkSavedHandlers)
						handler(m.cwp, m.snapshots);
				}
			);
		}
	}

	void loadChunk(ChunkWorldPos cwp) {
		auto m = new LoadSnapshotMessage(cwp, genWorkers.nextWorker);
		storeWorker.send(cast(immutable(LoadSnapshotMessage)*)m);
		++loadQueueLength;
	}

	void saveChunk(ChunkWorldPos cwp, BlockDataSnapshot[] snapshots) {
		auto m = new SaveSnapshotMessage(cwp, snapshots);
		storeWorker.send(cast(immutable(SaveSnapshotMessage)*)m);
	}
}
