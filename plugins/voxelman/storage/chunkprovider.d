/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.storage.chunkprovider;

import std.concurrency : spawn, Tid;
import std.experimental.logger;
import core.atomic;

import dlib.math.vector;

import voxelman.core.chunkgen;
import voxelman.core.config;
import voxelman.storage.chunk;
import voxelman.storage.chunkstorage;
import voxelman.storage.coordinates;
import voxelman.world.worlddb : WorldDb;
import voxelman.utils.sharedqueue;
import voxelman.storage.storageworker;


alias MessageQueue = SharedQueue!(ulong, QUEUE_LENGTH);

struct ChunkProvider
{
	private Tid storeWorker;
	private shared bool workerRunning = true;
	private shared bool workerStopped = false;

	size_t numReceived;

	shared MessageQueue loadResQueue;
	shared MessageQueue saveResQueue;
	shared MessageQueue loadTaskQueue;
	shared MessageQueue saveTaskQueue;

	void delegate() onChunkLoadedHandler;
	void delegate() onChunkSavedHandler;

	size_t loadQueueSpaceAvaliable() @property const {
		long space = cast(long)loadTaskQueue.capacity - loadTaskQueue.length;
		return space >= 0 ? space : 0;
	}

	void init(WorldDb worldDb, uint numGenWorkers) {
		loadResQueue.alloc();
		saveResQueue.alloc();
		loadTaskQueue.alloc();
		saveTaskQueue.alloc();
		storeWorker = spawn(&storageWorker, cast(immutable)worldDb, &workerRunning, &workerStopped,
			&loadResQueue, &saveResQueue, &loadTaskQueue, &saveTaskQueue);
	}

	void stop() {
		bool queuesEmpty() {
			return loadResQueue.empty && saveResQueue.empty && loadTaskQueue.empty && saveTaskQueue.empty;
		}
		while (!queuesEmpty()) {
			update();
		}
		atomicStore!(MemoryOrder.rel)(workerRunning, false);
		while (!atomicLoad!(MemoryOrder.acq)(workerStopped))
			Thread.yield();
	}

	void free() {
		loadResQueue.free();
		saveResQueue.free();
		loadTaskQueue.free();
		saveTaskQueue.free();
	}

	size_t prevReceived = size_t.max;
	void update() {
		//infof("%s %s %s %s", loadResQueue.length, saveResQueue.length,
		//		loadTaskQueue.length, saveTaskQueue.length);
		while(loadResQueue.length > 0)
		{
			onChunkLoadedHandler();
			++numReceived;
		}
		while(!saveResQueue.empty)
		{
			//infof("Save res received");
			onChunkSavedHandler();
			++numReceived;
		}

		if (prevReceived != numReceived)
			version(DBG_OUT)infof("ChunkProvider running %s", numReceived);
		prevReceived = numReceived;
	}
}
