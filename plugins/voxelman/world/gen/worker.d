/**
Copyright: Copyright (c) 2013-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.gen.worker;

import voxelman.log;

import voxelman.container.sharedhashset;
import voxelman.world.block;
import voxelman.core.config;
import voxelman.utils.worker;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.chunk;
import voxelman.world.storage.chunkprovider : TaskId, TASK_CANCELED_METADATA;

import voxelman.world.gen.utils;
import voxelman.world.gen.generator;

//version = DBG_OUT;
void chunkGenWorkerThread(
	shared(Worker)* workerInfo,
	shared SharedHashSet!TaskId canceledTasks,
	BlockInfoTable blockInfos)
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
				TaskId taskId = workerInfo.taskQueue.popItem!TaskId();
				ulong _cwp = workerInfo.taskQueue.popItem!ulong();
				ChunkWorldPos cwp = ChunkWorldPos(_cwp);
				IGenerator generator = workerInfo.taskQueue.popItem!IGenerator();

				if (canceledTasks[taskId])
				{
					workerInfo.resultQueue.startMessage();
					workerInfo.resultQueue.pushMessagePart(taskId);
					workerInfo.resultQueue.pushMessagePart(ChunkHeaderItem(cwp, 0, TASK_CANCELED_METADATA));
					workerInfo.resultQueue.endMessage();

					continue;
				}

				genChunk(taskId, cwp, &workerInfo.resultQueue,
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
	TaskId taskId,
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
	resultQueue.pushMessagePart(taskId);
	resultQueue.pushMessagePart(ChunkHeaderItem(cwp, numLayers));

	if(chunk.uniform)
	{
		ushort metadata = calcChunkFullMetadata(chunk.uniformBlockId, blockInfos);
		auto layer = ChunkLayerItem(layerId,
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
