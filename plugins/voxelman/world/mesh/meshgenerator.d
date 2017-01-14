/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.mesh.meshgenerator;

import voxelman.log;
import std.conv : to;
import core.exception : Throwable;

import voxelman.container.buffer;
import voxelman.math;
import voxelman.geometry.box;
import voxelman.geometry.cube;

import voxelman.world.block;
import voxelman.world.blockentity;
import voxelman.world.mesh.chunkmesh;
import voxelman.world.storage.arraycopy;
import voxelman.core.config;
import voxelman.utils.worker;
import voxelman.world.storage;

import voxelman.world.mesh.utils;
import voxelman.world.mesh.blockmesher;
import voxelman.world.mesh.extendedchunk;

void genGeometry(const ref ExtendedChunk chunk,
	ChunkLayerItem[27] entityLayers,
	BlockEntityInfoTable beInfos,
	SeparatedBlockInfoTable blockInfoTable,
	ref Buffer!MeshVertex[3] geometry)
{
	//const BlockInfo[] blockInfos = blockInfoTable.blockInfos;
	foreach (layer; entityLayers)
		assert(layer.type != StorageType.compressedArray, "[MESHING] Data needs to be uncompressed 2");

	BlockEntityMap[27] maps;
	foreach (i, layer; entityLayers) maps[i] = getHashMapFromLayer(layer);

	BlockEntityData getBlockEntity(ushort blockIndex, BlockEntityMap map) {
		ulong* entity = blockIndex in map;
		if (entity is null) return BlockEntityData.init;
		return BlockEntityData(*entity);
	}

	//BlockShape getShape(BlockId blockId)
	//{
	//	if (isBlockEntity(blockId)) {
	//		ushort entityBlockIndex = blockIndexFromBlockId(blockId);
	//		BlockEntityData data = getBlockEntity(entityBlockIndex, maps[26]);
	//		return beInfos[data.id].blockShape(entityBlockIndex, data);
	//	} else {
	//		return blockInfoTable.shapes[blockId];
	//	}
	//}

	pragma(inline, true)
	ShapeSideMask getSideMask(size_t blockIndex, ubyte side)
	{
		BlockId blockId = chunk.allBlocks.ptr[blockIndex];
		if (isBlockEntity(blockId)) {
			ushort entityBlockIndex = blockIndexFromBlockId(blockId);
			BlockEntityData data = getBlockEntity(entityBlockIndex, maps[26]);
			auto entityChunkPos = BlockChunkPos(entityBlockIndex);
			ivec3 blockChunkPos = BlockChunkPos(cast(ushort)blockIndex).vector - ivec3(1,1,1);
			ivec3 blockEntityPos = blockChunkPos - entityChunkPos.vector;
			return beInfos[data.id].blockShape(blockEntityPos, data).sideMasks[side];
		} else {
			return blockInfoTable.sideMasks[blockId][side];
		}
	}

	pragma(inline, true)
	bool isSideRendered(size_t blockIndex, ubyte side, const ShapeSideMask currentMask)
	{
		return blockInfoTable.sideTable.get(currentMask, getSideMask(blockIndex, side));
	}

	ubyte checkSideSolidities(const ref ShapeSideMask[6] sideMasks, size_t index)
	{
		ubyte sides = 0;

		sides |= isSideRendered(index + sideIndexOffsets[0], 1, sideMasks[0]) << 0;
		sides |= isSideRendered(index + sideIndexOffsets[1], 0, sideMasks[1]) << 1;
		sides |= isSideRendered(index + sideIndexOffsets[2], 3, sideMasks[2]) << 2;
		sides |= isSideRendered(index + sideIndexOffsets[3], 2, sideMasks[3]) << 3;
		sides |= isSideRendered(index + sideIndexOffsets[4], 5, sideMasks[4]) << 4;
		sides |= isSideRendered(index + sideIndexOffsets[5], 4, sideMasks[5]) << 5;

		return sides;
	}

	// assumes that block to the side has lower solidity than current block
	// 0--3 // corner numbering of face verticies
	// |\ |
	// 1--2
	ubyte getCorners(size_t blockIndex)
	{
		BlockId blockId = chunk.allBlocks.ptr[blockIndex];

		if (isBlockEntity(blockId)) {
			ushort entityBlockIndex = blockIndexFromBlockId(blockId);
			BlockEntityData data = getBlockEntity(entityBlockIndex, maps[26]);

			auto entityChunkPos = BlockChunkPos(entityBlockIndex);
			ivec3 blockChunkPos = BlockChunkPos(cast(ushort)blockIndex).vector - ivec3(1,1,1);
			ivec3 blockEntityPos = blockChunkPos - entityChunkPos.vector;

			return beInfos[data.id].blockShape(blockEntityPos, data).corners;
		} else {
			return blockInfoTable.corners[blockId];
		}
	}

	ubyte[4] calcFaceCornerOcclusions(ushort blockIndex, CubeSide side)
	{
		int index = blockIndex + sideIndexOffsets[side];

		ubyte cornersT = getCorners(index + faceSideIndexOffset[side][0]);
		ubyte cornersL = getCorners(index + faceSideIndexOffset[side][1]);
		ubyte cornersB = getCorners(index + faceSideIndexOffset[side][2]);
		ubyte cornersR = getCorners(index + faceSideIndexOffset[side][3]);
		ubyte[12] faceCornersToAdjCorners = faceSideCorners[side];

		bool getCorner(ubyte corners, ubyte tableIndex)
		{
			return (corners & (1 << faceCornersToAdjCorners[tableIndex])) > 0;
		}

		ubyte result0 = getCorner(cornersT, 0) << 1 | getCorner(cornersL, 2) << 2;
		if (result0 < 6) result0 |= getCorner(getCorners(index + faceSideIndexOffset[side][4]), 1);

		ubyte result1 = getCorner(cornersL, 3) << 1 | getCorner(cornersB, 5) << 2;
		if (result1 < 6) result1 |= getCorner(getCorners(index + faceSideIndexOffset[side][5]), 4);

		ubyte result2 = getCorner(cornersB, 6) << 1 | getCorner(cornersR, 8) << 2;
		if (result2 < 6) result2 |= getCorner(getCorners(index + faceSideIndexOffset[side][6]), 7);

		ubyte result3 = getCorner(cornersR, 9) << 1 | getCorner(cornersT, 11) << 2;
		if (result3 < 6) result3 |= getCorner(getCorners(index + faceSideIndexOffset[side][7]), 10);

		return [result0, result1, result2, result3];
	}

	void meshBlock(BlockId blockId, ushort index, ubvec3 bpos)
	{
		const BlockInfo binfo = blockInfoTable.blockInfos[blockId];
		if (binfo.isVisible)
		{
			ubyte sides = checkSideSolidities(binfo.shape.sideMasks, index);

			if (binfo.shape.hasInternalGeometry || sides != 0)
			{
				auto data = BlockMeshingData(
					&geometry[binfo.solidity],
					&calcFaceCornerOcclusions,
					binfo.color,
					bpos,
					sides,
					index);
				binfo.meshHandler(data);
			}
		}
	}

	void meshBlockEntity(BlockId blockId, ushort index, ubvec3 bpos)
	{
		ubyte sides = checkSideSolidities(fullShapeSides, index);
		ushort entityBlockIndex = blockIndexFromBlockId(blockId);
		BlockEntityData data = getBlockEntity(entityBlockIndex, maps[26]);

		// entity chunk pos
		auto entityChunkPos = BlockChunkPos(entityBlockIndex);

		ivec3 blockChunkPos = ivec3(bpos);
		ivec3 blockEntityPos = blockChunkPos - entityChunkPos.vector;

		auto entityInfo = beInfos[data.id];

		auto meshingData = BlockEntityMeshingData(
			geometry,
			&calcFaceCornerOcclusions,
			entityInfo.color,
			sides,
			blockChunkPos,
			blockEntityPos,
			data,
			index);

		entityInfo.meshHandler(meshingData);
	}

	size_t index = extendedChunkIndex(1, 1, 1);

	foreach (ubyte y; 0..CHUNK_SIZE)
	{
		foreach (ubyte z; 0..CHUNK_SIZE)
		{
			foreach (ubyte x; 0..CHUNK_SIZE)
			{
				BlockId blockId = chunk.allBlocks.ptr[index];
				ubvec3 bpos = ubvec3(x, y, z);

				if (isBlockEntity(blockId))
				{
					meshBlockEntity(blockId, cast(ushort)index, bpos);
				}
				else
				{
					meshBlock(blockId, cast(ushort)index, bpos);
				}

				++index;
			}
			index +=2;
		}
		index += EXTENDED_CHUNK_SIZE*2;
	}
}
