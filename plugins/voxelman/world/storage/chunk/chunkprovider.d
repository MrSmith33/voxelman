/**
Copyright: Copyright (c) 2015-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.chunk.chunkprovider;

import voxelman.log;
import core.sync.condition;
import core.atomic;
import core.thread : Thread;
import std.string : format;

import voxelman.math;
import voxelman.container.sharedhashset;

import voxelman.world.block : BlockInfoTable;
import voxelman.core.config;
import voxelman.thread.worker;
import voxelman.world.gen.generator : IGenerator;
import voxelman.world.gen.utils;
import voxelman.world.gen.worker;
import voxelman.world.storage;
import voxelman.world.worlddb : WorldDb;


/// Used to pass data to chunkmanager's onSnapshotLoaded.
struct LoadedChunkData
{
	private ChunkHeaderItem header;
	private ChunkLayerItem[MAX_CHUNK_LAYERS] _layers;

	ChunkWorldPos cwp() { return header.cwp; }
	ChunkLayerItem[] layers() return { return _layers[0..header.numLayers]; }

	static LoadedChunkData getFromQueue(shared SharedQueue* queue) {
		LoadedChunkData data;
		assert(queue.length >= ChunkHeaderItem.sizeof);
		data.header = queue.popItem!ChunkHeaderItem;

		assert(queue.length >= ChunkLayerItem.sizeof * data.header.numLayers);
		assert(data.header.numLayers <= MAX_CHUNK_LAYERS,
			format("%s <= %s", data.header.numLayers, MAX_CHUNK_LAYERS));

		foreach(i; 0..data.header.numLayers)
		{
			data._layers[i] = queue.popItem!ChunkLayerItem;
		}
		return data;
	}
}

/// Used to pass data to chunkmanager's onSnapshotLoaded.
struct SavedChunkData
{
	private ChunkHeaderItem header;
	private ChunkLayerTimestampItem[MAX_CHUNK_LAYERS] _layers;

	ChunkWorldPos cwp() { return header.cwp; }
	ChunkLayerTimestampItem[] layers() return { return _layers[0..header.numLayers]; }

	static SavedChunkData getFromQueue(shared SharedQueue* queue) {
		SavedChunkData data;
		assert(queue.length >= ChunkHeaderItem.sizeof);
		data.header = queue.popItem!ChunkHeaderItem;

		assert(queue.length >= ChunkLayerTimestampItem.sizeof * data.header.numLayers);
		assert(data.header.numLayers <= MAX_CHUNK_LAYERS);

		foreach(i; 0..data.header.numLayers)
		{
			data._layers[i] = queue.popItem!ChunkLayerTimestampItem;
		}
		return data;
	}
}

alias IoHandler = void delegate(WorldDb);
alias TaskId = uint;

enum SaveItemType : ubyte {
	chunk,
	saveHandler
}

enum TASK_OK_METADATA = 0;
enum TASK_CANCELED_METADATA = 1;

//version = DBG_OUT;
final class ChunkProvider
{
	private Thread storeWorker;
	private shared bool workerRunning = true;
	private shared bool workerStopped = false;

	// metrics
	size_t totalReceived;
	size_t numWastedLoads;
	size_t numSuccessfulCancelations;

	private TaskId nextTaskId;

	Mutex workAvaliableMutex;
	Condition workAvaliable;
	shared SharedQueue loadResQueue;
	shared SharedQueue saveResQueue;
	shared SharedQueue loadTaskQueue;
	shared SharedQueue saveTaskQueue;

	shared SharedHashSet!TaskId canceledTasks;
	TaskId[ChunkWorldPos] chunkTasks;
	bool saveUnmodifiedChunks;

	shared Worker[] genWorkers;

	ChunkManager chunkManager;
	void delegate(ChunkWorldPos cwp, ChunkLayerItem[] layers, bool needsSave) onChunkLoadedHandler;
	void delegate(ChunkWorldPos cwp, ChunkLayerTimestampItem[] timestamps) onChunkSavedHandler;
	IGenerator delegate(DimensionId dimensionId) generatorGetter;

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

	this(ChunkManager chunkManager) {
		this.chunkManager = chunkManager;
	}

	void init(WorldDb worldDb, uint numGenWorkers, BlockInfoTable blocks, bool saveUnmodifiedChunks)
	{
		canceledTasks = cast(shared) new SharedHashSet!TaskId;
		this.saveUnmodifiedChunks = saveUnmodifiedChunks;

		import std.algorithm.comparison : clamp;
		numGenWorkers = clamp(numGenWorkers, 0, 16);
		genWorkers.length = numGenWorkers;
		foreach(i; 0..numGenWorkers)
		{
			genWorkers[i].alloc(0, "GEN_W", QUEUE_LENGTH);
			genWorkers[i].thread = cast(shared)spawnWorker(&chunkGenWorkerThread, &genWorkers[i], canceledTasks, blocks);
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
			canceledTasks,
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
		while(loadResQueue.length > 0)
		{
			receiveChunk(&loadResQueue, false);
		}
		while(!saveResQueue.empty)
		{
			auto data = SavedChunkData.getFromQueue(&saveResQueue);
			onSnapshotSaved(data.cwp, data.layers);
		}
		foreach(ref w; genWorkers)
		{
			while(!w.resultQueue.empty)
			{
				receiveChunk(&w.resultQueue, saveUnmodifiedChunks);
			}
		}

		if (prevReceived != totalReceived)
			version(DBG_OUT)infof("ChunkProvider running %s", totalReceived);
		prevReceived = totalReceived;
	}

	void loadChunk(ChunkWorldPos cwp)
	{
		IGenerator generator = generatorGetter(cwp.dimension);

		TaskId id = nextTaskId++;
		chunkTasks[cwp] = id;

		loadTaskQueue.startMessage();
		loadTaskQueue.pushMessagePart!TaskId(id);
		loadTaskQueue.pushMessagePart!ulong(cwp.asUlong);
		loadTaskQueue.pushMessagePart!IGenerator(generator);
		loadTaskQueue.endMessage();

		notify();
	}

	void cancelLoad(ChunkWorldPos cwp)
	{
		TaskId tid = chunkTasks[cwp];
		canceledTasks.put(tid);
		chunkTasks.remove(cwp);
	}

	void receiveChunk(shared(SharedQueue)* queue, bool needsSave)
	{
		TaskId loadedTaskId = queue.popItem!TaskId();

		auto data = LoadedChunkData.getFromQueue(queue);

		bool isFinalResult = false;
		// data is not marked as canceled
		if (data.header.metadata == TASK_OK_METADATA)
		{
			// data is for latest task -> send to chunk manager
			if (auto latestTaskId = data.cwp in chunkTasks)
			{
				if (loadedTaskId == *latestTaskId)
				{
					isFinalResult = true;
				}
			}
		}

		if (isFinalResult)
		{
			//assert(!canceledTasks[loadedTaskId]);
			onChunkLoadedHandler(data.cwp, data.layers, needsSave);
			chunkTasks.remove(data.cwp);
		}
		else
		{
			//assert(canceledTasks[loadedTaskId]);
			// update metrics
			if (data.header.metadata == TASK_OK_METADATA)
				++numWastedLoads;
			else
				++numSuccessfulCancelations;

			// data is for canceled request -> free arrays
			foreach(ref layer; data.layers)
				freeLayerArray(layer);
			canceledTasks.remove(loadedTaskId);
		}

		++totalReceived;
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

	/// Performs save of all modified chunks.
	/// Modified chunks are those that were committed.
	/// Perform save right after commit.
	void save() {
		foreach(cwp; chunkManager.getModifiedChunks()) {
			saveChunk(cwp);
		}
		chunkManager.clearModifiedChunks();
	}

	void saveChunk(ChunkWorldPos cwp) {
		saveTaskQueue.startMessage();
		saveTaskQueue.pushMessagePart(SaveItemType.chunk);
		size_t headerPos = saveTaskQueue.skipMessageItem!ChunkHeaderItem();

		uint numChunkLayers;
		foreach(ChunkLayerItem layerItem; chunkManager.iterateChunkSnapshotsAddUsers(cwp)) {
			saveTaskQueue.pushMessagePart(layerItem);
			++numChunkLayers;
		}

		saveTaskQueue.setItem(ChunkHeaderItem(cwp, numChunkLayers), headerPos);
		saveTaskQueue.endMessage();

		notify();
	}

	private void onSnapshotSaved(ChunkWorldPos cwp, ChunkLayerTimestampItem[] timestamps) {
		foreach(item; timestamps) {
			chunkManager.removeSnapshotUser(cwp, item.timestamp, item.layerId);
		}
	}
}
