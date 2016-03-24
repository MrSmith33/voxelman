/**
Copyright: Copyright (c) 2014-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.storage.storageworker;

import std.experimental.logger;
import std.conv : to;
import std.datetime : MonoTime, Duration, usecs, dur;

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

void storageWorkerThread(Tid mainTid, immutable WorldDb _worldDb)
{
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

	void writeChunk(ChunkWorldPos cwp, BlockDataSnapshot[] snapshots) {
		try {
			size_t encodedSize = encodeCbor(buffer[], snapshots.length);

			foreach(snap; snapshots)
			{
				encodedSize += encodeCbor(buffer[encodedSize..$], snap.timestamp);
				BlockData compressedData = snap.blockData;
				compressedData.blocks = compress(compressedData.blocks, compressBuffer);
				encodedSize += encodeCborArray(buffer[encodedSize..$], compressedData);
			}
			worldDb.savePerChunkData(cwp, 0, buffer[0..encodedSize]);
		} catch(Exception e) errorf("storage exception %s", e.to!string);
	}

	void doWrite(immutable(SaveSnapshotMessage)* message) {
		startTaskTiming("WR");
		auto m = cast(SaveSnapshotMessage*)message;
		writeChunk(m.cwp, m.snapshots);

		auto res = new SnapshotSavedMessage(m.cwp, m.snapshots);
		mainTid.send(cast(immutable(SnapshotSavedMessage)*)res);
		endTaskTiming();
	}

	void readChunk(immutable(LoadSnapshotMessage)* message) {
		startTaskTiming("RD");
		auto m = cast(LoadSnapshotMessage*)message;
		bool doGen;

		try
		{
		if (!doGen) {

			ubyte[] cborData = worldDb.loadPerChunkData(m.cwp, 0);
			scope(exit) worldDb.perChunkSelectStmt.reset();

			if (cborData !is null)
			{
				size_t numLayers = decodeCborSingle!size_t(cborData);
				BlockDataSnapshot[] snapshots;
				snapshots.length = numLayers;

				size_t i;
				while(cborData.length > 0 && i < numLayers)
				{
					TimestampType timestamp = decodeCborSingle!size_t(cborData);
					BlockData compressedData = decodeCborSingle!BlockData(cborData);
					BlockData blockData = compressedData;
					blockData.blocks = decompress(compressedData.blocks, compressBuffer);

					blockData.blocks = blockData.blocks.dup;
					//if (blockData.blocks.length > 0) {
					//	bool validLength = blockData.blocks.length == CHUNK_SIZE_CUBE;
					//	warningf(!validLength, "Wrong chunk data %s", m.cwp);
					//	if (validLength) {
					//		//m.blockBuffer[] = blockData.blocks;
					//	}
					//}
					//else
					//	blockData.blocks = null;

					snapshots[i] = BlockDataSnapshot(blockData, timestamp);
					++i;
				}

				auto res = new SnapshotLoadedMessage(m.cwp, snapshots, true);
				mainTid.send(cast(immutable(SnapshotLoadedMessage)*)res);
			}
			else doGen = true;
		}}
		catch(Exception e) {
			infof("storage exception %s regenerating %s", e.to!string, m.cwp);
			doGen = true;
		}
		if (doGen) m.genWorker.send(message);
		endTaskTiming();
	}

	bool isRunning = true;
	while (isRunning)
	{
		receive(
			(immutable(LoadSnapshotMessage)* message) {
				readChunk(message);
			},
			(immutable(SaveSnapshotMessage)* message) {
				doWrite(message);
			},
			(immutable IoHandler h) {
				h(worldDb);
			},
			(Variant v) {
				isRunning = false;
			}
		);
	}
	}
	catch(Throwable t)
	{
		infof("%s from storage worker", t.to!string);
		throw t;
	}
}
