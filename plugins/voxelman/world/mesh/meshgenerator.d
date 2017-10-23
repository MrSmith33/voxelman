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
import voxelman.geometry;

import voxelman.world.block;
import voxelman.world.blockentity;
import voxelman.world.mesh.chunkmesh;
import voxelman.algorithm.arraycopy3d;
import voxelman.core.config;
import voxelman.thread.worker;
import voxelman.world.storage;

import voxelman.world.mesh.config;
import voxelman.world.mesh.utils;
import voxelman.world.mesh.extendedchunk;

void genGeometry(const ref ExtendedChunk chunk,
	ChunkLayerItem[27] entityLayers,
	ChunkLayerItem[27] metadataLayers,
	BlockEntityInfoTable beInfos,
	SeparatedBlockInfoTable blockInfoTable,
	ref Buffer!MeshVertex[3] geometry)
{
	//const BlockInfo[] blockInfos = blockInfoTable.blockInfos;
	foreach (layer; entityLayers)
		assert(layer.type != StorageType.compressedArray, "[MESHING] Data needs to be uncompressed 2");

	BlockEntityMap[27] maps;
	foreach (i, layer; entityLayers) maps[i] = getHashMapFromLayer(layer);

	BlockEntityData getBlockEntity(ushort index, BlockEntityMap map) {
		ulong* entity = index in map;
		if (entity is null) return BlockEntityData.init;
		return BlockEntityData(*entity);
	}

	BlockShape getEntityShape(BlockId blockId, ushort index)
	{
		ushort entityBlockIndex = blockEntityIndexFromBlockId(blockId);
		auto cb = chunkAndBlockAt27FromExt(index);
		BlockEntityData data = getBlockEntity(entityBlockIndex, maps[cb.chunk]);
		auto entityChunkPos = BlockChunkPos(entityBlockIndex);
		ivec3 blockChunkPos = ivec3(cb.bx, cb.by, cb.bz);
		ivec3 blockEntityPos = blockChunkPos - entityChunkPos.vector;
		return beInfos[data.id].blockShape(blockChunkPos, blockEntityPos, data);
	}

	BlockShape getShape(BlockId blockId, ushort index)
	{
		if (isBlockEntity(blockId))
		{
			return getEntityShape(blockId, index);
		}
		else
		{
			if (blockInfoTable.shapeDependsOnMeta[blockId])
			{
				auto cb = chunkAndBlockAt27FromExt(index);
				auto blockMetadata = getLayerItemNoncompressed!BlockMetadata(metadataLayers[cb.chunk], BlockChunkIndex(cb.bx, cb.by, cb.bz));
				return blockInfoTable.shapeMetaHandler[blockId](blockMetadata);
			}
			else
			{
				return blockInfoTable.shape[blockId];
			}
		}
	}

	//pragma(inline, true)
	ShapeSideMask getSideMask(ushort index, ubyte side)
	{
		BlockId blockId = chunk.allBlocks.ptr[index];
		return getShape(blockId, index).sideMasks[side];
	}

	//pragma(inline, true)
	bool isSideRendered(size_t index, ubyte side, const ShapeSideMask currentMask)
	{
		return blockInfoTable.sideTable.get(currentMask, getSideMask(cast(ushort)index, side));
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
	//pragma(inline, true)
	ubyte getCorners(size_t index)
	{
		BlockId blockId = chunk.allBlocks.ptr[index];
		return getShape(blockId, cast(ushort)index).corners;
	}

	static if (AO_ENABLED)
	ubyte[4] calcFaceCornerOcclusions(ushort blockIndex, CubeSide side)
	{
		int index = blockIndex + sideIndexOffsets[side];

		ubyte cornersC = getCorners(index);
		ubyte cornersT = getCorners(index + faceSideIndexOffset[side][0]);
		ubyte cornersL = getCorners(index + faceSideIndexOffset[side][1]);
		ubyte cornersB = getCorners(index + faceSideIndexOffset[side][2]);
		ubyte cornersR = getCorners(index + faceSideIndexOffset[side][3]);
		ubyte[16] faceCornersToAdjCorners = faceSideCorners4[side];

		bool getCorner(ubyte corners, ubyte tableIndex)
		{
			return (corners & (1 << faceCornersToAdjCorners[tableIndex])) != 0;
		}

		ubyte result0 = getCorner(cornersT, 1) | getCorner(cornersL, 3) << 1;
		if (result0 < 3) result0 |= getCorner(getCorners(index + faceSideIndexOffset[side][4]), 2) << 2;
		result0 |= getCorner(cornersC, 0) << 3;

		ubyte result1 = getCorner(cornersL, 5) | getCorner(cornersB, 7) << 1;
		if (result1 < 3) result1 |= getCorner(getCorners(index + faceSideIndexOffset[side][5]), 6) << 2;
		result1 |= getCorner(cornersC, 4) << 3;

		ubyte result2 = getCorner(cornersB, 9) | getCorner(cornersR, 11) << 1;
		if (result2 < 3) result2 |= getCorner(getCorners(index + faceSideIndexOffset[side][6]), 10) << 2;
		result2 |= getCorner(cornersC, 8) << 3;

		ubyte result3 = getCorner(cornersR, 13) | getCorner(cornersT, 15) << 1;
		if (result3 < 3) result3 |= getCorner(getCorners(index + faceSideIndexOffset[side][7]), 14) << 2;
		result3 |= getCorner(cornersC, 12) << 3;

		return [result0, result1, result2, result3];
	}

	static if (!AO_ENABLED)
	ubyte[4] calcFaceCornerOcclusions(ushort blockIndex, CubeSide side)
	{
		return [0,0,0,0];
	}

	void meshBlock(BlockId blockId, ushort index, ubvec3 bpos)
	{
		const BlockInfo binfo = blockInfoTable.blockInfos[blockId];
		if (binfo.isVisible)
		{
			auto shape = getShape(blockId, index);
			ubyte sides = checkSideSolidities(shape.sideMasks, index);

			if ((sides != 0) || shape.hasInternalGeometry)
			{
				BlockMetadata blockMetadata;
				if (binfo.meshDependOnMeta)
				{
					auto cb = chunkAndBlockAt27FromExt(cast(ushort)index);
					blockMetadata = getLayerItemNoncompressed!BlockMetadata(metadataLayers[cb.chunk], BlockChunkIndex(cb.bx, cb.by, cb.bz));
				}
				auto data = BlockMeshingData(
					&geometry[binfo.solidity],
					&calcFaceCornerOcclusions,
					binfo.color,
					binfo.uv,
					bpos,
					sides,
					index,
					blockMetadata);
				binfo.meshHandler(data);
			}
		}
	}

	void meshBlockEntity(BlockId blockId, ushort index, ubvec3 bpos)
	{
		ubyte sides = checkSideSolidities(getShape(blockId, index).sideMasks, index);
		ushort entityBlockIndex = blockEntityIndexFromBlockId(blockId);
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

struct SingleBlockMesher
{
	Buffer!MeshVertex geometry;

	void meshBlock(const BlockInfo binfo, BlockMetadata blockMetadata)
	{
		ubyte[4] calcFaceCornerOcclusions(ushort blockIndex, CubeSide side)
		{
			return [0,0,0,0];
		}

		auto data = BlockMeshingData(
			&geometry,
			&calcFaceCornerOcclusions,
			binfo.color,
			binfo.uv,
			ubvec3(0,0,0),
			0b111111,
			0,
			blockMetadata);
		binfo.meshHandler(data);
	}

	void reset()
	{
		geometry.clear();
	}
}
