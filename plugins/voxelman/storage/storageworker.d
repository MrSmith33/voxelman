/**
Copyright: Copyright (c) 2014-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.storage.storageworker;

import std.experimental.logger;
import std.conv : to;

import cbor;

import voxelman.core.config;
import voxelman.block.utils;
import voxelman.core.chunkgen;
import voxelman.storage.chunk;
import voxelman.storage.chunkprovider;
import voxelman.storage.coordinates;
import voxelman.storage.regionstorage;
import voxelman.world.worlddb;
import voxelman.utils.rlecompression;

private ubyte[4096*16] compressBuffer;
private ubyte[4096*16] buffer;

void storageWorkerThread(Tid mainTid, string worldFilename)
{
	try
	{
	//RegionStorage regionStorage = RegionStorage(regionDir);
	WorldDb worldDb;
	worldDb.openWorld(worldFilename);
	scope (exit) worldDb.close();

	shared(bool)* isRunning;
	bool isRunningLocal = true;
	receive( (shared(bool)* _isRunning){isRunning = _isRunning;} );

	void writeChunk(ChunkWorldPos cwp, BlockData data, TimestampType timestamp)
	{
		//if (regionStorage.isChunkOnDisk(cwp) &&
		//	timestamp <= regionStorage.chunkTimestamp(cwp)) return;

		BlockData compressedData = data;
		compressedData.blocks = rleEncode(data.blocks, compressBuffer);

		try
		{
			size_t encodedSize = encodeCborArray(buffer[], compressedData);
			//regionStorage.writeChunk(cwp, buffer[0..encodedSize], timestamp);
			worldDb.savePerChunkData(cwp, 0, timestamp, buffer[0..encodedSize]);
		}
		catch(Exception e)
		{
			errorf("storage exception %s", e.to!string);
		}
	}

	void doWrite(immutable(SaveSnapshotMessage)* message)
	{
		auto m = cast(SaveSnapshotMessage*)message;
		writeChunk(m.cwp, m.snapshot.blockData, m.snapshot.timestamp);

		auto res = new SnapshotSavedMessage(m.cwp, m.snapshot);
		mainTid.send(cast(immutable(SnapshotSavedMessage)*)res);
	}

	void readChunk(immutable(LoadSnapshotMessage)* message)
	{
		auto m = cast(LoadSnapshotMessage*)message;
		bool doGen;// = !regionStorage.isChunkOnDisk(m.cwp);

		try {
		if (!doGen) {
			TimestampType timestamp;
			//ubyte[] cborData = regionStorage.readChunk(m.cwp, buffer[], timestamp);
			ubyte[] cborData = worldDb.loadPerChunkData(m.cwp, 0, timestamp);
			scope(exit) worldDb.perChunkSelectStmt.reset();

			//infof("Read %s.%s.%s %s bytes", m.cwp.x, m.cwp.y, m.cwp.z, cborData.length);
			if (cborData !is null) {
				BlockData compressedData = decodeCborSingle!BlockData(cborData);
				BlockData blockData = compressedData;
				blockData.blocks = rleDecode(compressedData.blocks, compressBuffer);

				if (blockData.blocks.length > 0) {
					bool validLength = blockData.blocks.length == CHUNK_SIZE_CUBE;
					warningf(!validLength, "Wrong chunk data %s", m.cwp);

					if (validLength) {
						m.blockBuffer[] = blockData.blocks;
						blockData.blocks = m.blockBuffer;
					}
				}
				else
					blockData.blocks = m.blockBuffer;

				auto res = new SnapshotLoadedMessage(m.cwp, BlockDataSnapshot(blockData, timestamp));
				mainTid.send(cast(immutable(SnapshotLoadedMessage)*)res);
			}
			else
				doGen = true;
		}}
		catch(Exception e) {
			infof("storage exception %s regenerating %s", e.to!string, m.cwp);
			doGen = true;
		}

		if (doGen)
			m.genWorker.send(message);
	}

	while (isRunningLocal)
	{
		receive(
			// read
			(immutable(LoadSnapshotMessage)* message)
			{
				if (!atomicLoad(*isRunning))
					return;
				readChunk(message);
			},
			// write
			(immutable(SaveSnapshotMessage)* message)
			{
				doWrite(message);
			},
			(Variant v)
			{
				isRunningLocal = false;
				//regionStorage.clear();
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
