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

import voxelman.world.block;
import voxelman.world.mesh.chunkmesh;
import voxelman.world.storage.arraycopy;
import voxelman.core.config;
import voxelman.utils.worker;
import voxelman.world.storage;

import voxelman.world.mesh.utils;

struct SideParams
{
	ubvec3 blockPos;
	ubvec3 color;
	Buffer!MeshVertex* buffer;
}

float calcRandomTint(ushort index)
{
	return random(index)*0.1+0.9;
}

ubvec3 calcColor(ushort index, ubvec3 color)
{
	float randomTint = calcRandomTint(index);
	return ubvec3(
		color.r * randomTint,
		color.g * randomTint,
		color.b * randomTint);
}

immutable(float[]) shadowMultipliers = [
	0.7, 0.75, 0.6, 0.5, 0.85, 0.4,
];

enum AO_VALUE_0 = 0.70f;
enum AO_VALUE_1 = 0.80f;
enum AO_VALUE_2 = 0.9f;
enum AO_VALUE_3 = 1.0f;

__gshared immutable(float[]) occlusionTable = [
	            // LT C
	AO_VALUE_3, // 00 0 case 3
	AO_VALUE_2, // 00 1 case 2
	AO_VALUE_2, // 01 0 case 2
	AO_VALUE_1, // 01 1 case 1
	AO_VALUE_2, // 10 0 case 2
	AO_VALUE_1, // 10 1 case 1
	AO_VALUE_0, // 11 0 case 0
	AO_VALUE_0, // 11 1 case 0
];

void setExtendedArray(
	BlockId[] dest,
	ivec3 destPos,
	ChunkLayerItem source,
	Box sourceBox)
{
	if (source.isUniform)
		setSubArray(dest, EXTENDED_SIZE_VECTOR, Box(destPos, sourceBox.size), source.getUniform!BlockId);
	else
		setSubArray(dest, EXTENDED_SIZE_VECTOR, destPos, source.getArray!BlockId, CHUNK_SIZE_VECTOR, sourceBox);
}

struct ExtendedChunk
{
	BlockId[EXTENDED_CHUNK_SIZE_CUBE] allBlocks = void;

	// fill extended chunk with blocks from 27 chunks
	void create(ref ChunkLayerItem[27] blockLayers)
	{
		enum LAST_POS = CHUNK_SIZE - 1;
		enum EX_LAST_POS = EXTENDED_CHUNK_SIZE - 1;

		// bottom 9
		allBlocks[extendedChunkIndex(0, 0, 0)] = blockLayers[dirs3by3[0]].getBlockId(LAST_POS, LAST_POS, LAST_POS);
		allBlocks.setExtendedArray(ivec3(1, 0, 0), blockLayers[dirs3by3[1]], Box(ivec3(0, LAST_POS, LAST_POS), ivec3(CHUNK_SIZE, 1, 1)));
		allBlocks[extendedChunkIndex(EX_LAST_POS, 0, 0)] = blockLayers[dirs3by3[2]].getBlockId(0, LAST_POS, LAST_POS);
		allBlocks.setExtendedArray(ivec3(0, 0, 1), blockLayers[dirs3by3[3]], Box(ivec3(LAST_POS, LAST_POS, 0), ivec3(1, 1, CHUNK_SIZE)));
		allBlocks.setExtendedArray(ivec3(1, 0, 1), blockLayers[dirs3by3[4]], Box(ivec3(0, LAST_POS, 0), ivec3(CHUNK_SIZE, 1, CHUNK_SIZE)));
		allBlocks.setExtendedArray(ivec3(EX_LAST_POS, 0, 1), blockLayers[dirs3by3[5]], Box(ivec3(0, LAST_POS, 0), ivec3(1, 1, CHUNK_SIZE)));
		allBlocks[extendedChunkIndex(0, 0, EX_LAST_POS)] = blockLayers[dirs3by3[6]].getBlockId(LAST_POS, LAST_POS, 0);
		allBlocks.setExtendedArray(ivec3(1, 0, EX_LAST_POS), blockLayers[dirs3by3[7]], Box(ivec3(0, LAST_POS, 0), ivec3(CHUNK_SIZE, 1, 1)));
		allBlocks[extendedChunkIndex(EX_LAST_POS, 0, EX_LAST_POS)] = blockLayers[dirs3by3[8]].getBlockId(0, LAST_POS, 0);

		// middle 9
		allBlocks.setExtendedArray(ivec3(0, 1, 0), blockLayers[dirs3by3[9]], Box(ivec3(LAST_POS, 0, LAST_POS), ivec3(1, CHUNK_SIZE, 1)));
		allBlocks.setExtendedArray(ivec3(1, 1, 0), blockLayers[dirs3by3[10]], Box(ivec3(0, 0, LAST_POS), ivec3(CHUNK_SIZE, CHUNK_SIZE, 1)));
		allBlocks.setExtendedArray(ivec3(EX_LAST_POS, 1, 0), blockLayers[dirs3by3[11]], Box(ivec3(0, 0, LAST_POS), ivec3(1, CHUNK_SIZE, 1)));
		allBlocks.setExtendedArray(ivec3(0, 1, 1), blockLayers[dirs3by3[12]], Box(ivec3(LAST_POS, 0, 0), ivec3(1, CHUNK_SIZE, CHUNK_SIZE)));

		allBlocks.setExtendedArray(ivec3(1,1,1), blockLayers[26], Box(ivec3(0, 0, 0), CHUNK_SIZE_VECTOR));

		allBlocks.setExtendedArray(ivec3(EX_LAST_POS, 1, 1), blockLayers[dirs3by3[14]], Box(ivec3(0, 0, 0), ivec3(1, CHUNK_SIZE, CHUNK_SIZE)));
		allBlocks.setExtendedArray(ivec3(0, 1, EX_LAST_POS), blockLayers[dirs3by3[15]], Box(ivec3(LAST_POS, 0, 0), ivec3(1, CHUNK_SIZE, 1)));
		allBlocks.setExtendedArray(ivec3(1, 1, EX_LAST_POS), blockLayers[dirs3by3[16]], Box(ivec3(0, 0, 0), ivec3(CHUNK_SIZE, CHUNK_SIZE, 1)));
		allBlocks.setExtendedArray(ivec3(EX_LAST_POS, 1, EX_LAST_POS), blockLayers[dirs3by3[17]], Box(ivec3(0, 0, 0), ivec3(1, CHUNK_SIZE, 1)));

		// top 9
		allBlocks[extendedChunkIndex(0, EX_LAST_POS, 0)] = blockLayers[dirs3by3[18]].getBlockId(LAST_POS, 0, LAST_POS);
		allBlocks.setExtendedArray(ivec3(1, EX_LAST_POS, 0), blockLayers[dirs3by3[19]], Box(ivec3(0, 0, LAST_POS), ivec3(CHUNK_SIZE, 1, 1)));
		allBlocks[extendedChunkIndex(EX_LAST_POS, EX_LAST_POS, 0)] = blockLayers[dirs3by3[20]].getBlockId(0, 0, LAST_POS);
		allBlocks.setExtendedArray(ivec3(0, EX_LAST_POS, 1), blockLayers[dirs3by3[21]], Box(ivec3(LAST_POS, 0, 0), ivec3(1, 1, CHUNK_SIZE)));
		allBlocks.setExtendedArray(ivec3(1, EX_LAST_POS, 1), blockLayers[dirs3by3[22]], Box(ivec3(0, 0, 0), ivec3(CHUNK_SIZE, 1, CHUNK_SIZE)));
		allBlocks.setExtendedArray(ivec3(EX_LAST_POS, EX_LAST_POS, 1), blockLayers[dirs3by3[23]], Box(ivec3(0, 0, 0), ivec3(1, 1, CHUNK_SIZE)));
		allBlocks[extendedChunkIndex(0, EX_LAST_POS, EX_LAST_POS)] = blockLayers[dirs3by3[24]].getBlockId(LAST_POS, 0, 0);
		allBlocks.setExtendedArray(ivec3(1, EX_LAST_POS, EX_LAST_POS), blockLayers[dirs3by3[25]], Box(ivec3(0, 0, 0), ivec3(CHUNK_SIZE, 1, 1)));
		allBlocks[extendedChunkIndex(EX_LAST_POS, EX_LAST_POS, EX_LAST_POS)] = blockLayers[dirs3by3[26]].getBlockId(0, 0, 0);
	}
}

void meshSideOccluded(CubeSide side, ubyte[4] cornerOcclusion, SideParams d)
{
	immutable float mult = shadowMultipliers[side];
	//immutable float mult = 1;
	float r = mult * d.color.r;
	float g = mult * d.color.g;
	float b = mult * d.color.b;

	// Ambient occlusion multipliers
	float vert0AoMult = occlusionTable[cornerOcclusion[0]];
	float vert1AoMult = occlusionTable[cornerOcclusion[1]];
	float vert2AoMult = occlusionTable[cornerOcclusion[2]];
	float vert3AoMult = occlusionTable[cornerOcclusion[3]];

	immutable ubyte[3][4] finalColors = [
		[cast(ubyte)(vert0AoMult * r), cast(ubyte)(vert0AoMult * g), cast(ubyte)(vert0AoMult * b)],
		[cast(ubyte)(vert1AoMult * r), cast(ubyte)(vert1AoMult * g), cast(ubyte)(vert1AoMult * b)],
		[cast(ubyte)(vert2AoMult * r), cast(ubyte)(vert2AoMult * g), cast(ubyte)(vert2AoMult * b)],
		[cast(ubyte)(vert3AoMult * r), cast(ubyte)(vert3AoMult * g), cast(ubyte)(vert3AoMult * b)]];

	const(ubyte)[] faces;
	const(ubyte)[] faceIndexes;

	if(vert0AoMult + vert2AoMult > vert1AoMult + vert3AoMult)
	{
		faces = flippedCubeFaces[];
		faceIndexes = flippedFaceCornerIndexes[];
	}
	else
	{
		faces = cubeFaces[];
		faceIndexes = faceCornerIndexes[];
	}

	static struct MeshVertex3
	{
		align(4):
		float x, y, z;
		ubyte[3] color;
	}

	d.buffer.put(
		cast(MeshVertex)MeshVertex3(
			faces[18*side  ] + d.blockPos.x,
			faces[18*side+1] + d.blockPos.y,
			faces[18*side+2] + d.blockPos.z,
			finalColors[faceIndexes[0]]),
		cast(MeshVertex)MeshVertex3(
			faces[18*side+3] + d.blockPos.x,
			faces[18*side+4] + d.blockPos.y,
			faces[18*side+5] + d.blockPos.z,
			finalColors[faceIndexes[1]]),
		cast(MeshVertex)MeshVertex3(
			faces[18*side+6] + d.blockPos.x,
			faces[18*side+7] + d.blockPos.y,
			faces[18*side+8] + d.blockPos.z,
			finalColors[faceIndexes[2]]),
		cast(MeshVertex)MeshVertex3(
			faces[18*side+9] + d.blockPos.x,
			faces[18*side+10] + d.blockPos.y,
			faces[18*side+11] + d.blockPos.z,
			finalColors[faceIndexes[3]]),
		cast(MeshVertex)MeshVertex3(
			faces[18*side+12] + d.blockPos.x,
			faces[18*side+13] + d.blockPos.y,
			faces[18*side+14] + d.blockPos.z,
			finalColors[faceIndexes[4]]),
		cast(MeshVertex)MeshVertex3(
			faces[18*side+15] + d.blockPos.x,
			faces[18*side+16] + d.blockPos.y,
			faces[18*side+17] + d.blockPos.z,
			finalColors[faceIndexes[5]])
	);
}

void genGeometry(const ref ExtendedChunk chunk,
	ChunkLayerItem[27] entityLayers,
	BlockEntityInfoTable beInfos,
	BlockInfoTable blockInfoTable,
	ref Buffer!MeshVertex[3] geometry)
{
	const BlockInfo[] blockInfos = blockInfoTable.blockInfos;
	foreach (layer; entityLayers)
		assert(layer.type != StorageType.compressedArray, "[MESHING] Data needs to be uncompressed 2");

	BlockEntityMap[27] maps;
	foreach (i, layer; entityLayers) maps[i] = getHashMapFromLayer(layer);

	BlockEntityData getBlockEntity(ushort blockIndex, BlockEntityMap map) {
		ulong* entity = blockIndex in map;
		if (entity is null) return BlockEntityData.init;
		return BlockEntityData(*entity);
	}

	BlockShape getShape(BlockId blockId)
	{
		if (isBlockEntity(blockId)) {
			ushort entityBlockIndex = blockIndexFromBlockId(blockId);
			BlockEntityData data = getBlockEntity(entityBlockIndex, maps[26]);
			return beInfos[data.id].blockShape(entityBlockIndex, data);
		} else {
			return blockInfos[blockId].shape;
		}
	}

	bool isSideRendered(BlockId blockId, ubyte side, const ShapeSideMask currentMask)
	{
		return blockInfoTable.sideTable.get(currentMask, getShape(blockId).sideMasks[side]);
	}

	ubyte checkSideSolidities(const ref ShapeSideMask[6] sideMasks, size_t index)
	{
		ubyte sides = 0;

		sides |= isSideRendered(chunk.allBlocks[index + sideIndexOffsets[0]], 1, sideMasks[0]) << 0;
		sides |= isSideRendered(chunk.allBlocks[index + sideIndexOffsets[1]], 0, sideMasks[1]) << 1;
		sides |= isSideRendered(chunk.allBlocks[index + sideIndexOffsets[2]], 3, sideMasks[2]) << 2;
		sides |= isSideRendered(chunk.allBlocks[index + sideIndexOffsets[3]], 2, sideMasks[3]) << 3;
		sides |= isSideRendered(chunk.allBlocks[index + sideIndexOffsets[4]], 5, sideMasks[4]) << 4;
		sides |= isSideRendered(chunk.allBlocks[index + sideIndexOffsets[5]], 4, sideMasks[5]) << 5;

		return sides;
	}

	// assumes that block to the side has lower solidity than current block
	// 0--3 // corner numbering of face verticies
	// |\ |
	// 1--2
	ubyte getCorners(size_t blockIndex)
	{
		BlockId blockId = chunk.allBlocks.ptr[blockIndex];
		return getShape(blockId).corners;
	}

	ubyte[4] calcFaceCornerOcclusions(ushort blockIndex, ubyte side)
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

	void meshBlock(BlockId blockId, ushort index, ubvec3 bpos, const BlockInfo* binfo)
	{
		ubyte sides = checkSideSolidities(blockInfos[blockId].shape.sideMasks, index);

		if (sides != 0)
		{
			SideParams sideParams = SideParams(bpos, calcColor(index, binfo.color), &geometry[binfo.solidity]);
			//SideParams sideParams = SideParams(bpos, binfo.color, &geometry[binfo.solidity]);

			ubyte flag = 1;
			foreach(ubyte side; 0..6)
			{
				if (sides & flag)
				{
					ubyte[4] occlusions = calcFaceCornerOcclusions(index, side);
					meshSideOccluded(cast(CubeSide)side, occlusions, sideParams);
				}
				flag <<= 1;
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
			entityInfo.color,
			blockChunkPos,
			blockEntityPos,
			sides,
			data);

		entityInfo.meshHandler(meshingData);
	}

	size_t index = extendedChunkIndex(1, 1, 1);

	foreach (ubyte y; 1..CHUNK_SIZE+1)
	{
		foreach (ubyte z; 1..CHUNK_SIZE+1)
		{
			foreach (ubyte x; 1..CHUNK_SIZE+1)
			{
				BlockId blockId = chunk.allBlocks.ptr[index];

				if (isBlockEntity(blockId))
				{
					ubvec3 bpos = ubvec3(x-1, y-1, z-1);
					meshBlockEntity(blockId, cast(ushort)index, bpos);
				}
				else
				{
					const BlockInfo* binfo = &blockInfos[blockId];
					if (binfo.isVisible)
					{
						ubvec3 bpos = ubvec3(x-1, y-1, z-1);
						meshBlock(blockId, cast(ushort)index, bpos, binfo);
					}
				}

				++index;
			}
			index +=2;
		}
		index += EXTENDED_CHUNK_SIZE*2;
	}
}
