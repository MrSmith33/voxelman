/**
Copyright: Copyright (c) 2014-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.storage.storageworker;

import std.experimental.logger;
import std.conv : to;
import std.datetime : MonoTime, Duration, usecs, dur, seconds;
import core.atomic;

import cbor;

import voxelman.core.config;
import voxelman.block.utils;
import voxelman.core.chunkgen;
import voxelman.storage.chunk;
import voxelman.storage.chunkprovider;
import voxelman.storage.coordinates;
import voxelman.storage.regionstorage;
import voxelman.world.worlddb;
import voxelman.world.plugin : IoHandler;
import voxelman.utils.compression;


struct TimeMeasurer
{
	TimeMeasurer* nested;
	TimeMeasurer* next;
	MonoTime startTime;
	Duration takenTime;
	string taskName;
	bool wasRun = false;

	void reset()
	{
		wasRun = false;
		takenTime = Duration.zero;
		if (nested) nested.reset();
		if (next) next.reset();
	}

	void startTaskTiming(string name)
	{
		taskName = name;
		startTime = MonoTime.currTime;
	}

	void endTaskTiming()
	{
		wasRun = true;
		takenTime = MonoTime.currTime - startTime;
	}

	void printTime(bool isNested = false)
	{
		int seconds; short msecs; short usecs;
		takenTime.split!("seconds", "msecs", "usecs")(seconds, msecs, usecs);
		if (msecs > 10 || seconds > 0 || isNested)
		{
			if (wasRun)
				infof("%s%s %s.%s,%ss", isNested?"  ":"", taskName, seconds, msecs, usecs);
			if (nested) nested.printTime(true);
			if (next) next.printTime(isNested);
		}
	}
}

//version = DBG_OUT;
//version = DBG_COMPR;
void storageWorker(
			immutable WorldDb _worldDb,
			shared bool* workerRunning,
			shared bool* workerStopped,
			shared MessageQueue* loadResQueue,
			shared MessageQueue* saveResQueue,
			shared MessageQueue* loadTaskQueue,
			shared MessageQueue* saveTaskQueue,
			shared Worker[] genWorkers,
			)
{
	version(DBG_OUT)infof("Storage worker started");
	infof("genWorkers.length %s", genWorkers.length);
	try
	{
	ubyte[] compressBuffer = new ubyte[](4096*16);
	ubyte[] buffer = new ubyte[](4096*16);
	WorldDb worldDb = cast(WorldDb)_worldDb;
	scope(exit) worldDb.close();

	TimeMeasurer taskTime;
	TimeMeasurer workTime;
	TimeMeasurer readTime;
	taskTime.nested = &readTime;
	readTime.next = &workTime;

	void writeChunk()
	{
		taskTime.reset();
		taskTime.startTaskTiming("WR");

		ChunkHeaderItem header = saveTaskQueue.popItem!ChunkHeaderItem();

		saveResQueue.startPush();
		saveResQueue.pushItem(header);
		try
		{
			size_t encodedSize = encodeCbor(buffer[], header.numLayers);

			foreach(_; 0..header.numLayers)
			{
				ChunkLayerItem layer = saveTaskQueue.popItem!ChunkLayerItem();

				encodedSize += encodeCbor(buffer[encodedSize..$], layer.timestamp);
				encodedSize += encodeCbor(buffer[encodedSize..$], layer.layerId);
				encodedSize += encodeCbor(buffer[encodedSize..$], layer.metadata);
				if (layer.type == StorageType.uniform)
				{
					encodedSize += encodeCbor(buffer[encodedSize..$], layer.type);
					encodedSize += encodeCbor(buffer[encodedSize..$], cast(BlockId)layer.uniformData);
				}
				else if (layer.type == StorageType.fullArray)
				{
					encodedSize += encodeCbor(buffer[encodedSize..$], StorageType.compressedArray);
					BlockId[] blocks = layer.getArray!BlockId;
					ubyte[] compactBlocks = compress(cast(ubyte[])blocks, compressBuffer);
					encodedSize += encodeCbor(buffer[encodedSize..$], compactBlocks);
					version(DBG_COMPR)infof("Store1 %s %s %s\n(%(%02x%))", header.cwp, compactBlocks.ptr, compactBlocks.length, cast(ubyte[])compactBlocks);
				}
				else if (layer.type == StorageType.compressedArray)
				{
					encodedSize += encodeCbor(buffer[encodedSize..$], layer.type);
					ubyte[] compactBlocks = layer.getArray!ubyte;
					encodedSize += encodeCbor(buffer[encodedSize..$], compactBlocks);
					version(DBG_COMPR)infof("Store2 %s %s %s\n(%(%02x%))", header.cwp, compactBlocks.ptr, compactBlocks.length, cast(ubyte[])compactBlocks);
				}

				saveResQueue.pushItem(ChunkLayerTimestampItem(layer.timestamp, layer.layerId));
			}

			worldDb.putPerChunkValue(header.cwp.asUlong, buffer[0..encodedSize]);
		}
		catch(Exception e) errorf("storage exception %s", e.to!string);
		saveResQueue.endPush();
		taskTime.endTaskTiming();
		taskTime.printTime();
		version(DBG_OUT)infof("task save %s", header.cwp);
	}

	size_t _nextWorker;
	immutable size_t numWorkers = genWorkers.length;
	assert(numWorkers > 0);
	static struct QLen {size_t i; size_t len;}
	QLen[] queueLengths;
	queueLengths.length = numWorkers;
	shared(MessageQueue)* nextGenQueue()
	{
		import std.algorithm : sort;
		foreach(i; 0..numWorkers)
		{
			queueLengths[i].i = i;
			queueLengths[i].len = genWorkers[i].taskQueue.length;
		}
		sort!((a,b) => a.len < b.len)(queueLengths);// balance worker queues
		//_nextWorker = (_nextWorker + 1) % numWorkers;
		return &genWorkers[queueLengths[0].i].taskQueue;
	}

	//BlockData {
	//	BlockId[] blocks;
	//	BlockId uniformType = 0;
	//	bool uniform = true;
	//}
	void readChunk()
	{
		taskTime.reset();
		taskTime.startTaskTiming("RD");
		bool doGen;

		ulong cwp = loadTaskQueue.popItem!ulong();

		try
		{
			readTime.startTaskTiming("getPerChunkValue");
			ubyte[] cborData = worldDb.getPerChunkValue(cwp);
			readTime.endTaskTiming();
			//scope(exit) worldDb.perChunkSelectStmt.reset();

			if (cborData !is null)
			{
				workTime.startTaskTiming("decode");
				ubyte numLayers = decodeCborSingle!ubyte(cborData);
				// TODO check numLayers <= ubyte.max
				bool saved = true;
				loadResQueue.startPush();
				loadResQueue.pushItem(ChunkHeaderItem(ChunkWorldPos(cwp), cast(ubyte)numLayers, cast(uint)saved));
				foreach(_; 0..numLayers)
				{
					auto timestamp = decodeCborSingle!TimestampType(cborData);
					auto layerId = decodeCborSingle!ubyte(cborData);
					auto metadata = decodeCborSingle!ushort(cborData);
					auto type = decodeCborSingle!StorageType(cborData);

					if (type == StorageType.uniform)
					{
						BlockId uniformData = decodeCborSingle!BlockId(cborData);
						loadResQueue.pushItem(ChunkLayerItem(StorageType.uniform, layerId, 0, timestamp, uniformData, metadata));
					}
					else
					{
						import core.memory : GC;
						assert(type == StorageType.compressedArray);
						ubyte[] compactBlocks = decodeCborSingle!(ubyte[])(cborData);
						compactBlocks = compactBlocks.dup;
						ushort dataLength = cast(ushort)compactBlocks.length;
						ubyte* data = cast(ubyte*)compactBlocks.ptr;

						// Add root to data.
						// Data can be collected by GC if no-one is referencing it.
						// It is needed to pass array trough shared queue.
						GC.addRoot(data); // TODO remove when moved to non-GC allocator
						version(DBG_COMPR)infof("Load %s L %s C (%(%02x%))", ChunkWorldPos(cwp), compactBlocks.length, cast(ubyte[])compactBlocks);
						loadResQueue.pushItem(ChunkLayerItem(StorageType.compressedArray, layerId, dataLength, timestamp, data, metadata));
					}
				}
				loadResQueue.endPush();
				// if (cborData.length > 0) error; TODO
				workTime.endTaskTiming();
			}
			else doGen = true;
		}
		catch(Exception e) {
			infof("storage exception %s regenerating %s", e.to!string, ChunkWorldPos(cwp));
			doGen = true;
		}
		if (doGen) {
			nextGenQueue().pushSingleItem!ulong(cwp);
		}
		taskTime.endTaskTiming();
		taskTime.printTime();
		version(DBG_OUT)infof("task load %s", ChunkWorldPos(cwp));
	}

	uint numReceived;
	MonoTime frameStart = MonoTime.currTime;
	size_t prevReceived = size_t.max;
	while (*atomicLoad(workerRunning))
	{
		worldDb.beginTxn();
		while(!loadTaskQueue.empty)
		{
			readChunk();
			++numReceived;
		}
		worldDb.abortTxn();

		worldDb.beginTxn();
		while(!saveTaskQueue.empty)
		{
			writeChunk();
			++numReceived;
		}
		worldDb.commitTxn();

		if (prevReceived != numReceived)
			version(DBG_OUT)infof("Storage worker running %s %s", numReceived, *atomicLoad(workerRunning));
		prevReceived = numReceived;

		auto now = MonoTime.currTime;
		auto dur = now - frameStart;
		if (dur > 3.seconds) {
			//infof("Storage update");
			frameStart = now;
		}
	}
	}
	catch(Throwable t)
	{
		infof("%s from storage worker", t.to!string);
		throw t;
	}
	version(DBG_OUT)infof("Storage worker stopped (%s, %s)", numReceived, *atomicLoad(workerRunning));
	atomicStore!(MemoryOrder.rel)(*workerStopped, true);
}
