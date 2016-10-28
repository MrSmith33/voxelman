/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.chunkprovider;

import voxelman.log;
import core.sync.condition;
import core.atomic;
import core.thread : Thread;

import voxelman.math;

import voxelman.block.utils : BlockInfoTable;
import voxelman.core.config;
import voxelman.utils.worker;
import voxelman.world.gen.utils;
import voxelman.world.gen.worker;
import voxelman.world.storage;
import voxelman.world.worlddb : WorldDb;

enum saveUnmodifiedChunks = true;

/// Used to pass data to chunkmanager's onSnapshotLoaded.
struct LoadedChunkData
{
	private shared(SharedQueue)* queue;
	ChunkHeaderItem getHeader()
	{
		assert(queue.length >= ChunkHeaderItem.sizeof);
		ChunkHeaderItem header;
		queue.popItem(header);
		assert(queue.length >= ChunkLayerItem.sizeof * header.numLayers);
		return header;
	}
	ChunkLayerItem getLayer()
	{
		return queue.popItem!ChunkLayerItem;
	}
}

/// Used to pass data to chunkmanager's onSnapshotLoaded.
struct SavedChunkData
{
	private shared(SharedQueue)* queue;
	ChunkHeaderItem getHeader()
	{
		assert(queue.length >= 2);
		ChunkHeaderItem header;
		queue.popItem(header);
		assert(queue.length >= ChunkLayerItem.sizeof/8 * header.numLayers);
		return header;
	}
	ChunkLayerTimestampItem getLayerTimestamp()
	{
		ChunkLayerTimestampItem layer;
		queue.popItem(layer);
		return layer;
	}
}

alias IoHandler = void delegate(WorldDb);

enum SaveItemType : ubyte {
	chunk,
	saveHandler
}

//version = DBG_OUT;
struct ChunkProvider
{
	private Thread storeWorker;
	private shared bool workerRunning = true;
	private shared bool workerStopped = false;

	size_t numReceived;

	Mutex workAvaliableMutex;
	Condition workAvaliable;
	shared SharedQueue loadResQueue;
	shared SharedQueue saveResQueue;
	shared SharedQueue loadTaskQueue;
	shared SharedQueue saveTaskQueue;

	shared Worker[] genWorkers;

	void delegate(LoadedChunkData loadedChunk, bool needsSave) onChunkLoadedHandler;
	void delegate(SavedChunkData savedChunk) onChunkSavedHandler;

	size_t loadQueueSpaceAvaliable() @property const {
		ptrdiff_t space = cast(ptrdiff_t)loadTaskQueue.capacity - loadTaskQueue.length;
		return space >= 0 ? space : 0;
	}

	void notify()
	{
		synchronized (workAvaliableMutex)
		{
			workAvaliable.notify();
		}
	}

	void init(WorldDb worldDb, uint numGenWorkers, BlockInfoTable blocks)
	{
		import std.algorithm.comparison : clamp;
		numGenWorkers = clamp(numGenWorkers, 0, 16);
		genWorkers.length = numGenWorkers;
		foreach(i; 0..numGenWorkers)
		{
			genWorkers[i].alloc("GEN_W", QUEUE_LENGTH);
			genWorkers[i].thread = cast(shared)spawnWorker(&chunkGenWorkerThread, &genWorkers[i], blocks);
		}

		workAvaliableMutex = new Mutex;
		workAvaliable = new Condition(workAvaliableMutex);
		loadResQueue.alloc("loadResQ", QUEUE_LENGTH);
		saveResQueue.alloc("saveResQ", QUEUE_LENGTH);
		loadTaskQueue.alloc("loadTaskQ", QUEUE_LENGTH);
		saveTaskQueue.alloc("saveTaskQ", QUEUE_LENGTH);
		storeWorker = spawnWorker(
			&storageWorker, cast(immutable)worldDb,
			&workerRunning,
			cast(shared)workAvaliableMutex, cast(shared)workAvaliable,
			&loadResQueue, &saveResQueue, &loadTaskQueue, &saveTaskQueue,
			genWorkers);
	}

	void stop() {
		bool queuesEmpty() {
			return loadResQueue.empty && saveResQueue.empty && loadTaskQueue.empty && saveTaskQueue.empty;
		}
		bool allWorkersStopped() {
			bool stopped = !storeWorker.isRunning;
			foreach(ref w; genWorkers) stopped = stopped && w.isStopped;
			return stopped;
		}

		while (!queuesEmpty()) {
			if(!saveTaskQueue.empty || !loadTaskQueue.empty)
			{
				notify();
			}
			update();
		}

		atomicStore!(MemoryOrder.rel)(workerRunning, false);
		notify();
		foreach(ref w; genWorkers) w.stop();

		while (!allWorkersStopped())
		{
			Thread.yield();
		}

		free();
	}

	private void free() {
		loadResQueue.free();
		saveResQueue.free();
		loadTaskQueue.free();
		saveTaskQueue.free();
		foreach(ref w; genWorkers) {
			w.free();
		}
	}

	size_t prevReceived = size_t.max;
	void update() {
		//infof("%s %s %s %s", loadResQueue.length, saveResQueue.length,
		//		loadTaskQueue.length, saveTaskQueue.length);
		while(loadResQueue.length > 0)
		{
			onChunkLoadedHandler(LoadedChunkData(&loadResQueue), false);
			++numReceived;
		}
		while(!saveResQueue.empty)
		{
			//infof("Save res received");
			onChunkSavedHandler(SavedChunkData(&saveResQueue));
			++numReceived;
		}
		foreach(ref w; genWorkers)
		{
			while(!w.resultQueue.empty)
			{
				//infof("Save res received");
				onChunkLoadedHandler(LoadedChunkData(&w.resultQueue), saveUnmodifiedChunks);
				++numReceived;
			}
		}

		if (prevReceived != numReceived)
			version(DBG_OUT)infof("ChunkProvider running %s", numReceived);
		prevReceived = numReceived;
	}

	void loadChunk(ChunkWorldPos cwp)
	{
		loadTaskQueue.pushItem!ulong(cwp.asUlong);
		notify();
	}

	// sends a delegate to IO thread
	void pushSaveHandler(IoHandler ioHandler)
	{
		saveTaskQueue.startMessage();
		saveTaskQueue.pushMessagePart(SaveItemType.saveHandler);
		saveTaskQueue.pushMessagePart(ioHandler);
		saveTaskQueue.endMessage();
		notify();
	}

	size_t startChunkSave()
	{
		saveTaskQueue.startMessage();
		saveTaskQueue.pushMessagePart(SaveItemType.chunk);
		size_t headerPos = saveTaskQueue.skipMessageItem!ChunkHeaderItem();
		return headerPos;
	}
	void pushLayer(ChunkLayerItem layer)
	{
		saveTaskQueue.pushMessagePart(layer);
	}
	void endChunkSave(size_t headerPos, ChunkHeaderItem header)
	{
		saveTaskQueue.setItem(header, headerPos);
		saveTaskQueue.endMessage();
		notify();
	}
}
