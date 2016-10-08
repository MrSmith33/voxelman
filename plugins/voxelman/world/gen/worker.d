/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.gen.worker;

import voxelman.log;

import voxelman.block.utils;
import voxelman.core.config;
import voxelman.utils.worker;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.chunk;

import voxelman.world.gen.utils;
import voxelman.world.gen.generator;

//version = DBG_OUT;
void chunkGenWorkerThread(shared(Worker)* workerInfo, BlockInfoTable blockInfos)
{
	import std.array : uninitializedArray;

	ubyte[] compressBuffer = uninitializedArray!(ubyte[])(CHUNK_SIZE_CUBE*BlockId.sizeof);
	try
	{
		while (workerInfo.needsToRun)
		{
			workerInfo.waitForNotify();

			if (!workerInfo.taskQueue.empty)
			{
				ulong _cwp = workerInfo.taskQueue.popItem!ulong();
				ChunkWorldPos cwp = ChunkWorldPos(_cwp);
				IGenerator generator = workerInfo.taskQueue.popItem!IGenerator();
				genChunk(cwp, &workerInfo.resultQueue,
					generator, blockInfos, compressBuffer);
			}
		}
	}
	catch(Throwable t)
	{
		import std.conv : to;
		infof("%s from gen worker", t.to!string);
		throw t;
	}
	version(DBG_OUT)infof("Gen worker stopped");
}

//version = DBG_COMPR;
void genChunk(
	ChunkWorldPos cwp,
	shared(SharedQueue)* resultQueue,
	IGenerator generator,
	BlockInfoTable blockInfos,
	ubyte[] compressBuffer)
{
	BlockId[CHUNK_SIZE_CUBE] blocks;
	ChunkGeneratorResult chunk = generator.generateChunk(
		cwp.xyz, blocks);

	enum layerId = FIRST_LAYER;
	enum timestamp = 0;
	enum numLayers = 1;

	resultQueue.startMessage();
	auto header = ChunkHeaderItem(cwp, numLayers);
	resultQueue.pushMessagePart(header);

	if(chunk.uniform)
	{
		ushort metadata = calcChunkFullMetadata(chunk.uniformBlockId, blockInfos);
		auto layer = ChunkLayerItem(StorageType.uniform, layerId,
			BLOCKID_UNIFORM_FILL_BITS, timestamp,
			chunk.uniformBlockId, metadata);
		resultQueue.pushMessagePart(layer);
	}
	else
	{
		ushort metadata = calcChunkFullMetadata(blocks, blockInfos);
		ubyte[] compactBlocks = compressLayerData(cast(ubyte[])blocks, compressBuffer);
		StorageType storageType = StorageType.compressedArray;
		ubyte[] data = allocLayerArray(compactBlocks);

		auto layer = ChunkLayerItem(storageType, layerId, timestamp, data, metadata);
		resultQueue.pushMessagePart(layer);
	}
	resultQueue.endMessage();
}
