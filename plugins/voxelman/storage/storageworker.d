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


//version = DBG_OUT;
void storageWorker(
			immutable WorldDb _worldDb,
			//uint numGenWorkers,
			shared bool* workerRunning,
			shared bool* workerStopped,
			shared MessageQueue* loadResQueue,
			shared MessageQueue* saveResQueue,
			shared MessageQueue* loadTaskQueue,
			shared MessageQueue* saveTaskQueue,
			//shared MessageQueue*[] genResQueue,
			)
{
	uint numReceived;
	version(DBG_OUT)infof("Storage worker started");

	try
	{
	ubyte[] compressBuffer = new ubyte[](4096*16);
	ubyte[] buffer = new ubyte[](4096*16);
	WorldDb worldDb = cast(WorldDb)_worldDb;
	scope(exit) worldDb.close();

	MonoTime prevTime;
	string taskName;
	void startTaskTiming(string name)
	{
		taskName = name;
		prevTime = MonoTime.currTime;
	}

	void endTaskTiming()
	{
		Duration past = MonoTime.currTime - prevTime;
		int seconds; short msecs; short usecs;
		past.split!("seconds", "msecs", "usecs")(seconds, msecs, usecs);
		if (msecs > 10 || seconds > 0)
			infof("%s %s.%s,%ss", taskName, seconds, msecs, usecs);
	}

	void writeChunk() {
		startTaskTiming("WR");

		ChunkHeaderItem header = saveTaskQueue.popItem!ChunkHeaderItem();

		saveResQueue.startPush();
		saveResQueue.pushItem(header);
		try {
			size_t encodedSize = encodeCbor(buffer[], header.numLayers);

			// TODO encode layerId
			foreach(_; 0..header.numLayers) {
				ChunkLayerItem layer = saveTaskQueue.popItem!ChunkLayerItem();

				encodedSize += encodeCbor(buffer[encodedSize..$], layer.timestamp);
				BlockData compressedData;
				compressedData.uniform = layer.type == StorageType.uniform;
				if (!compressedData.uniform) {
					compressedData.blocks = (cast(BlockId*)layer.dataPtr)[0..layer.dataLength];
					compressedData.blocks = compress(compressedData.blocks, compressBuffer);
				} else
					compressedData.uniformType = cast(BlockId)layer.uniformData;
				encodedSize += encodeCborArray(buffer[encodedSize..$], compressedData);

				saveResQueue.pushItem(ChunkLayerTimestampItem(layer.timestamp, layer.layerId));
			}

			worldDb.savePerChunkData(header.cwp.asUlong, 0, buffer[0..encodedSize]);
		} catch(Exception e) errorf("storage exception %s", e.to!string);
		saveResQueue.endPush();
		endTaskTiming();
		version(DBG_OUT)infof("task save %s", header.cwp);
	}

	//BlockData {
	//	BlockId[] blocks;
	//	BlockId uniformType = 0;
	//	bool uniform = true;
	//}
	void readChunk() {
		startTaskTiming("RD");
		bool doGen;

		ulong cwp = loadTaskQueue.popItem!ulong();

		try
		{
			ubyte[] cborData = worldDb.loadPerChunkData(cwp);
			scope(exit) worldDb.perChunkSelectStmt.reset();

			if (cborData !is null)
			{
				ubyte numLayers = decodeCborSingle!ubyte(cborData);
				// TODO check numLayers <= ubyte.max
				bool saved = true;
				loadResQueue.startPush();
				loadResQueue.pushItem(ChunkHeaderItem(ChunkWorldPos(cwp), cast(ubyte)numLayers, cast(uint)saved));
				// TODO decode layerId
				foreach(ubyte layerId; 0..numLayers) {
					auto timestamp = decodeCborSingle!TimestampType(cborData);
					BlockData compressedData = decodeCborSingle!BlockData(cborData);

					if (compressedData.uniform)
						loadResQueue.pushItem(ChunkLayerItem(StorageType.uniform, layerId, 0, timestamp, compressedData.uniformType));
					else {
						BlockId[] blocks = decompress(compressedData.blocks, compressBuffer);
						blocks = blocks.dup;
						ushort dataLength = cast(ushort)blocks.length;
						ubyte* data = cast(ubyte*)blocks.ptr;
						loadResQueue.pushItem(ChunkLayerItem(StorageType.fullArray, layerId, dataLength, timestamp, data));
					}
				}
				loadResQueue.endPush();
				// if (cborData.length > 0) error; TODO
			}
			else doGen = true;
		}
		catch(Exception e) {
			infof("storage exception %s regenerating %s", e.to!string, ChunkWorldPos(cwp));
			doGen = true;
		}
		if (doGen) {
			loadResQueue.startPush();
			loadResQueue.pushItem(ChunkHeaderItem(ChunkWorldPos(cwp), cast(ubyte)1, cast(uint)true));
			loadResQueue.pushItem(ChunkLayerItem(StorageType.uniform, 0, 0, 0, 0));
			loadResQueue.endPush();
			//genWorker.send(message); TODO gen
		}
		endTaskTiming();
		version(DBG_OUT)infof("task load %s", ChunkWorldPos(cwp));
	}

	MonoTime frameStart = MonoTime.currTime;
	size_t prevReceived = size_t.max;
	while (*atomicLoad(workerRunning))
	{
		while(!loadTaskQueue.empty)
		{
			readChunk();
			++numReceived;
		}

		while(!saveTaskQueue.empty)
		{
			writeChunk();
			++numReceived;
		}
		if (prevReceived != numReceived)
			version(DBG_OUT)infof("Storage worker running %s %s", numReceived, *atomicLoad(workerRunning));
		prevReceived = numReceived;

		auto now = MonoTime.currTime;
		auto dur = now - frameStart;
		if (dur > 3.seconds) {
			infof("Storage update");
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
