/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.mesh.meshgen;

import voxelman.log;
import std.conv : to;
import core.exception : Throwable;

import voxelman.container.buffer;
import voxelman.math;
import voxelman.geometry.cube;

import voxelman.block.plugin;
import voxelman.blockentity.plugin;

import voxelman.block.utils;
import voxelman.world.mesh.chunkmesh;
import voxelman.core.config;
import voxelman.utils.worker;
import voxelman.world.storage;


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
	// reusable buffers
	Buffer!MeshVertex[3] geometry; // 2 - solid, 1 - semiTransparent
	try
	{
		while (workerInfo.needsToRun)
		{
			workerInfo.waitForNotify();

			// receive
			//   MeshGenTaskHeader taskHeader;
			//   ChunkLayerItem[7] blockLayers;
			//   ChunkLayerItem[7] entityLayers;
			// or
			//   MeshGenTaskHeader taskHeader;
			//
			// send
			//   MeshGenTaskHeader taskHeader;
			//   MeshVertex[][2] meshes;
			//   uint[7] blockTimestamps;
			//   uint[7] entityTimestamps;
			// or
			//   MeshGenTaskHeader taskHeader;
			if (!workerInfo.taskQueue.empty)
			{
				auto taskHeader = workerInfo.taskQueue.popItem!MeshGenTaskHeader();

				if (taskHeader.type == MeshGenTaskType.genMesh)
				{
					// get mesh task.
					auto blockLayers = workerInfo.taskQueue.popItem!(ChunkLayerItem[27]);
					auto entityLayers = workerInfo.taskQueue.popItem!(ChunkLayerItem[27]);

					MeshVertex[][2] meshes = chunkMeshWorker(blockLayers, entityLayers, blockInfos, beInfos, geometry);

					uint[27] blockTimestamps;
					uint[27] entityTimestamps;
					foreach(i; 0..27) blockTimestamps[i] = blockLayers[i].timestamp;
					foreach(i; 0..27) entityTimestamps[i] = entityLayers[i].timestamp;

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

MeshVertex[][2] chunkMeshWorker(
	ChunkLayerItem[27] blockLayers,
	ChunkLayerItem[27] entityLayers,
	BlockInfoTable blockInfos,
	BlockEntityInfoTable beInfos,
	ref Buffer!MeshVertex[3] geometry)
{
	foreach (layer; blockLayers) {
		assert(layer.type != StorageType.compressedArray, "[MESHING] Data needs to be uncompressed 1");
		if (!layer.isUniform)
			assert(layer.getArray!ubyte.length == BLOCKS_DATA_LENGTH);
	}
	foreach (layer; entityLayers)
		assert(layer.type != StorageType.compressedArray, "[MESHING] Data needs to be uncompressed 2");

	BlockEntityMap[27] maps;
	foreach (i, layer; entityLayers) maps[i] = getHashMapFromLayer(layer);

	BlockEntityData getBlockEntity(ushort blockIndex, BlockEntityMap map) {
		ulong* entity = blockIndex in map;
		if (entity is null) return BlockEntityData.init;
		return BlockEntityData(*entity);
	}

	Solidity solidity(int tx, int ty, int tz, CubeSide side)
	{
		ChunkAndBlockAt chAndBlock = chunkAndBlockAt6(tx, ty, tz);
		BlockId blockId = blockLayers[chAndBlock.chunk].getBlockId(
			chAndBlock.blockX, chAndBlock.blockY, chAndBlock.blockZ);

		if (isBlockEntity(blockId)) {
			ushort entityBlockIndex = blockIndexFromBlockId(blockId);
			BlockEntityData data = getBlockEntity(entityBlockIndex, maps[chAndBlock.chunk]);
			auto entityInfo = beInfos[data.id];

			auto entityChunkPos = BlockChunkPos(entityBlockIndex);

			ivec3 blockChunkPos = ivec3(chAndBlock.blockX, chAndBlock.blockY, chAndBlock.blockZ);
			ivec3 blockEntityPos = blockChunkPos - entityChunkPos.vector;

			return entityInfo.sideSolidity(side, blockChunkPos, blockEntityPos, data);
		} else {
			return blockInfos[blockId].solidity;
		}
	}

	BlockId[27] collectBlocks3by3(ubvec3 bpos) const {
		BlockId[27] result;
		foreach(i, offset; offsets3by3) {
			auto cb = chunkAndBlockAt27(bpos.x+offset[0], bpos.y+offset[1], bpos.z+offset[2]);
			result[i] = blockLayers[cb.chunk].getBlockId(cb.blockX, cb.blockY, cb.blockZ);
		}
		return result;
	}

	Solidity[27] collectSolidities3by3(ubvec3 bpos) const {
		Solidity[27] result;
		foreach(i, blockId; collectBlocks3by3(bpos)) {
			result[i] = blockInfos[blockId].solidity;
		}
		return result;
	}

	ubyte checkSideSolidities(Solidity curSolidity, ubvec3 bpos)
	{
		ubyte sides = 0;
		ubyte flag = 1;
		foreach(ubyte side; 0..6) {
			byte[3] offset = sideOffsets6[side]; // Offset to adjacent block
			if(curSolidity > solidity(bpos.x+offset[0], bpos.y+offset[1], bpos.z+offset[2], oppSide[side])) {
				sides |= flag;
			}
			flag <<= 1;
		}
		return sides;
	}

	void meshBlock(BlockId blockId, ubyte x, ubyte y, ubyte z, Solidity curSolidity)
	{
		ubvec3 bpos = ubvec3(x, y, z);

		// Bit flags of sides to render
		ubyte sides = checkSideSolidities(curSolidity, bpos);
		Solidity[27] solidities;// = collectSolidities3by3(bpos);

		if (isBlockEntity(blockId))
		{
			ushort entityBlockIndex = blockIndexFromBlockId(blockId);
			BlockEntityData data = getBlockEntity(entityBlockIndex, maps[26]);

			// entity chunk pos
			auto entityChunkPos = BlockChunkPos(entityBlockIndex);

			ivec3 blockChunkPos = ivec3(bpos);
			ivec3 blockEntityPos = blockChunkPos - entityChunkPos.vector;

			auto entityInfo = beInfos[data.id];

			auto meshingData = BlockEntityMeshingData(
				geometry,
				entityInfo.color,
				blockChunkPos,
				blockEntityPos,
				sides,
				data);

			entityInfo.meshHandler(meshingData);
		}
		else
		{
			auto data = BlockMeshingData(
				&geometry[curSolidity],
				blockInfos[blockId].color,
				bpos,
				sides);
			blockInfos[blockId].meshHandler(data);
		}
	}

	if (blockLayers[26].isUniform)
	{
		BlockId blockId = blockLayers[26].getUniform!BlockId;
		Meshhandler meshHandler = blockInfos[blockId].meshHandler;
		ubvec3 color = blockInfos[blockId].color;
		Solidity curSolidity = blockInfos[blockId].solidity;

		if (curSolidity != Solidity.transparent)
		{
			foreach (ubyte y; 0..CHUNK_SIZE)
			foreach (ubyte z; 0..CHUNK_SIZE)
			foreach (ubyte x; 0..CHUNK_SIZE)
			{
				meshBlock(blockId, x, y, z, curSolidity);
			}
		}
	}
	else
	{
		auto blocks = blockLayers[26].getArray!BlockId();
		assert(blocks.length == CHUNK_SIZE_CUBE);

		ushort index = 0;

		foreach (ubyte y; 0..CHUNK_SIZE)
		foreach (ubyte z; 0..CHUNK_SIZE)
		foreach (ubyte x; 0..CHUNK_SIZE)
		{
			BlockId blockId = blocks.ptr[index];
			if (blockInfos[blockId].isVisible)
			{
				Solidity curSolidity = blockInfos[blockId].solidity;
				meshBlock(blockId, x, y, z, curSolidity);
			}
			++index;
		}
	}

	MeshVertex[][2] meshes;

	import std.experimental.allocator;
	import std.experimental.allocator.mallocator;
	meshes[0] = makeArray!MeshVertex(Mallocator.instance, geometry[2].data); // solid geometry
	meshes[1] = makeArray!MeshVertex(Mallocator.instance, geometry[1].data); // semi-transparent geometry


	geometry[1].clear();
	geometry[2].clear();

	return meshes;
}
