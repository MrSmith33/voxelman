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

shared struct Worker
{
	Thread thread;
	bool running = true;
	MessageQueue taskQueue;
	MessageQueue resultQueue;

	// for owner
	void alloc() shared {
		taskQueue.alloc();
		resultQueue.alloc();
	}

	// for owner
	void stop() shared {
		atomicStore!(MemoryOrder.rel)(running, false);
	}

	// for worker
	void signalStopped() shared {
		atomicStore!(MemoryOrder.rel)(running, false);
	}

	bool isRunning() shared @property {
		return atomicLoad!(MemoryOrder.acq)(running) && (cast(Thread)thread).isRunning;
	}

	bool isStopped() shared @property const {
		return !(cast(Thread)thread).isRunning;
	}

	bool queuesEmpty() shared @property const {
		return taskQueue.empty && resultQueue.empty;
	}

	// for owner
	void free() shared {
		taskQueue.free();
		resultQueue.free();
	}
}

Thread spawnWorker(F, T...)(F fn, T args)
{
	void exec()
	{
		fn( args );
	}
	auto t = new Thread(&exec);
    t.start();
    return t;
}

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

	shared Worker[] genWorkers;

	void delegate(shared(MessageQueue)* queue, bool generated) onChunkLoadedHandler;
	void delegate() onChunkSavedHandler;

	size_t loadQueueSpaceAvaliable() @property const {
		long space = cast(long)loadTaskQueue.capacity - loadTaskQueue.length;
		return space >= 0 ? space : 0;
	}

	void init(WorldDb worldDb, uint numGenWorkers)
	{
		import std.algorithm.comparison : clamp;
		numGenWorkers = clamp(numGenWorkers, 1, 16);
		genWorkers.length = numGenWorkers;
		foreach(i; 0..numGenWorkers)
		{
			genWorkers[i].alloc();
			genWorkers[i].thread = cast(shared)spawnWorker(&chunkGenWorkerThread, &genWorkers[i]);
		}

		loadResQueue.alloc();
		saveResQueue.alloc();
		loadTaskQueue.alloc();
		saveTaskQueue.alloc();
		storeWorker = spawn(&storageWorker, cast(immutable)worldDb, &workerRunning, &workerStopped,
			&loadResQueue, &saveResQueue, &loadTaskQueue, &saveTaskQueue, genWorkers);
	}

	void stop() {
		bool queuesEmpty() {
			bool empty = loadResQueue.empty && saveResQueue.empty && loadTaskQueue.empty && saveTaskQueue.empty;
			foreach(ref w; genWorkers) empty = empty && w.queuesEmpty;
			return empty;
		}
		bool allWorkersStopped() {
			bool stopped = atomicLoad!(MemoryOrder.acq)(workerStopped);
			foreach(ref w; genWorkers) stopped = stopped && w.isStopped;
			return stopped;
		}

		while (!queuesEmpty()) {
			update();
		}

		atomicStore!(MemoryOrder.rel)(workerRunning, false);
		foreach(ref w; genWorkers) w.stop();

		while (!allWorkersStopped())
		{
			Thread.sleep(50.usecs);
		}
	}

	void free() {
		loadResQueue.free();
		saveResQueue.free();
		loadTaskQueue.free();
		saveTaskQueue.free();
		foreach(ref w; genWorkers)
			w.free();
	}

	size_t prevReceived = size_t.max;
	void update() {
		//infof("%s %s %s %s", loadResQueue.length, saveResQueue.length,
		//		loadTaskQueue.length, saveTaskQueue.length);
		while(loadResQueue.length > 0)
		{
			onChunkLoadedHandler(&loadResQueue, true);
			++numReceived;
		}
		while(!saveResQueue.empty)
		{
			//infof("Save res received");
			onChunkSavedHandler();
			++numReceived;
		}
		foreach(ref w; genWorkers)
		{
			while(!w.resultQueue.empty)
			{
				//infof("Save res received");
				onChunkLoadedHandler(&w.resultQueue, false);
				++numReceived;
			}
		}

		if (prevReceived != numReceived)
			version(DBG_OUT)infof("ChunkProvider running %s", numReceived);
		prevReceived = numReceived;
	}
}
