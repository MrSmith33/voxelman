/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.core.meshgen;

import std.experimental.logger;
import std.array : Appender;
import std.conv : to;
import core.exception : Throwable;
import core.sync.semaphore;


import voxelman.block.plugin;
import voxelman.block.utils;
import voxelman.blockentity.utils;
import voxelman.blockentity.blockentityaccess;
import voxelman.blockentity.blockentitymap;

import voxelman.core.config;
import voxelman.world.storage.chunk;
import voxelman.world.storage.coordinates;
import voxelman.utils.worker;


enum MeshGenTaskType : ubyte
{
	genMesh,
	unloadMesh
}

struct MeshGenTaskHeader
{
	MeshGenTaskType type;
	size_t meshGroupId;
	ChunkWorldPos cwp;
}

//version = DBG_OUT;
void meshWorkerThread(shared(Worker)* workerInfo, BlockInfoTable blockInfos, BlockEntityInfoTable beInfos)
{
	try
	{
		while (workerInfo.needsToRun)
		{
			(cast(Semaphore)workerInfo.workAvaliable).wait();

			// receive
			//   MeshGenTaskHeader taskHeader;
			//   ChunkLayerItem[7] blockLayers;
			//   ChunkLayerItem[7] entityLayers;
			// or
			//   MeshGenTaskHeader taskHeader;
			//
			// send
			//   MeshGenTaskHeader taskHeader;
			//   ubyte[][2] meshes;
			//   uint[7] blockTimestamps;
			//   uint[7] entityTimestamps;
			// or
			//   MeshGenTaskHeader taskHeader;
			if (!workerInfo.taskQueue.empty)
			{
				auto taskHeader = workerInfo.taskQueue.popItem!MeshGenTaskHeader();

				if (taskHeader.type == MeshGenTaskType.genMesh)
				{
					// mesh task.
					ChunkLayerItem[7] blockLayers = workerInfo.taskQueue.popItem!(ChunkLayerItem[7])();
					ChunkLayerItem[7] entityLayers = workerInfo.taskQueue.popItem!(ChunkLayerItem[7])();

					ubyte[][2] meshes = chunkMeshWorker(blockLayers, entityLayers, blockInfos, beInfos);

					uint[7] blockTimestamps;
					uint[7] entityTimestamps;
					foreach(i; 0..7) blockTimestamps[i] = blockLayers[i].timestamp;
					foreach(i; 0..7) entityTimestamps[i] = entityLayers[i].timestamp;

					workerInfo.resultQueue.startMessage();
					workerInfo.resultQueue.pushMessagePart(taskHeader);
					workerInfo.resultQueue.pushMessagePart(meshes);
					workerInfo.resultQueue.pushMessagePart(blockTimestamps);
					workerInfo.resultQueue.pushMessagePart(entityTimestamps);
					workerInfo.resultQueue.endMessage();
				}
				else
				{
					// remove mesh task. Resend it to main thread.
					workerInfo.resultQueue.pushItem(taskHeader);
				}
			}
		}
	}
	catch(Throwable t)
	{
		infof("%s from mesh worker", t.to!string);
		throw t;
	}
	version(DBG_OUT)infof("Mesh worker stopped");
}

ubyte[][2] chunkMeshWorker(ChunkLayerItem[7] blockLayers,
	ChunkLayerItem[7] entityLayers, BlockInfoTable blockInfos, BlockEntityInfoTable beInfos)
{
	Appender!(ubyte[])[3] geometry; // 2 - solid, 1 - semiTransparent

	foreach (layer; blockLayers)
		assert(layer.type != StorageType.compressedArray, "[MESHING] Data needs to be uncompressed");

	BlockEntityMap[7] maps;
	foreach (i, layer; entityLayers) maps[i] = getHashMapFromLayer(layer);

	BlockEntityData getBlockEntity(ushort blockIndex, BlockEntityMap map) {
		ulong* entity = blockIndex in map;
		if (entity is null) return BlockEntityData.init;
		return BlockEntityData(*entity);
	}

	Solidity solidity(int tx, int ty, int tz, Side side)
	{
		ChunkAndBlockAt chAndBlock = chunkAndBlockAt(tx, ty, tz);
		BlockId blockId = blockLayers[chAndBlock.chunk].getBlockId(
			chAndBlock.blockX, chAndBlock.blockY, chAndBlock.blockZ);

		if (isBlockEntity(blockId)) {
			ushort blockIndex = blockIndexFromBlockId(blockId);
			BlockEntityData data = getBlockEntity(blockIndex, maps[chAndBlock.chunk]);
			auto entityInfo = beInfos[data.id];
			return entityInfo.sideSolidity(side);
		} else {
			return blockInfos[blockId].solidity;
		}
	}

	ubyte checkSideSolidities(Solidity curSolidity, ubyte bx, ubyte by, ubyte bz)
	{
		ubyte sides = 0;
		ubyte flag = 1;
		foreach(ubyte side; 0..6) {
			byte[3] offset = sideOffsets[side]; // Offset to adjacent block
			if(curSolidity > solidity(bx+offset[0], by+offset[1], bz+offset[2], oppSide[side])) {
				sides |= flag;
			}
			flag <<= 1;
		}
		return sides;
	}

	void meshBlock(BlockId blockId, ushort blockIndex, Solidity curSolidity)
	{
		ubyte bx = blockIndex & CHUNK_SIZE_BITS;
		ubyte by = (blockIndex / CHUNK_SIZE_SQR) & CHUNK_SIZE_BITS;
		ubyte bz = (blockIndex / CHUNK_SIZE) & CHUNK_SIZE_BITS;

		// Bit flags of sides to render
		ubyte sides = checkSideSolidities(curSolidity, bx, by, bz);

		if (isBlockEntity(blockId))
		{
			ushort entityBlockIndex = blockIndexFromBlockId(blockId);
			BlockEntityData data = getBlockEntity(entityBlockIndex, maps[6]);

			// entity chunk pos
			auto entityChunkPos = BlockChunkPos(entityBlockIndex);

			//ivec3 worldPos;
			ivec3 blockChunkPos = ivec3(bx, by, bz);
			ivec3 blockEntityPos = blockChunkPos - entityChunkPos.vector;

			auto entityInfo = beInfos[data.id];

			entityInfo.meshHandler(
				geometry[],
				data,
				entityInfo.color,
				sides,
				//worldPos,
				blockChunkPos,
				blockEntityPos);
		}
		else
		{
			blockInfos[blockId].meshHandler(geometry[curSolidity], blockInfos[blockId].color, bx, by, bz, sides);
		}
	}

	if (blockLayers[6].isUniform)
	{
		BlockId blockId = blockLayers[6].getUniform!BlockId;
		Meshhandler meshHandler = blockInfos[blockId].meshHandler;
		ubyte[3] color = blockInfos[blockId].color;
		Solidity curSolidity = blockInfos[blockId].solidity;

		if (curSolidity != Solidity.transparent)
		{
			foreach (ushort index; 0..CHUNK_SIZE_CUBE)
			{
				meshBlock(blockId, index, curSolidity);
			}
		}
	}
	else
	{
		auto blocks = blockLayers[6].getArray!BlockId();
		assert(blocks.length == CHUNK_SIZE_CUBE);
		foreach (ushort index, BlockId blockId; blocks)
		{
			if (blockInfos[blockId].isVisible)
			{
				auto curSolidity = blockInfos[blockId].solidity;
				if (curSolidity == Solidity.transparent)
					continue;

				meshBlock(blockId, index, curSolidity);
			}
		}
	}

	ubyte[][2] meshes;
	meshes[0] = geometry[2].data; // solid geometry
	meshes[1] = geometry[1].data; // semi-transparent geometry

	// Add root to data.
	// Data can be collected by GC if no-one is referencing it.
	// It is needed to pass array trough shared queue.
	// Root is removed inside ChunkMeshMan
	import core.memory : GC;
	if (meshes[0]) GC.addRoot(meshes[0].ptr); // TODO remove when moved to non-GC allocator
	if (meshes[1]) GC.addRoot(meshes[1].ptr); //

	return meshes;
}
