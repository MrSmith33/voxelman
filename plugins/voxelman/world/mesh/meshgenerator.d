/**
Copyright: Copyright (c) 2016 Andrey Penechko.
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

import voxelman.block.plugin;
import voxelman.blockentity.plugin;

import voxelman.block.utils;
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

struct MeshingTable
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

	void genGeometry(ref Buffer!MeshVertex[3] geometry, const BlockInfo[] blockInfos)
	{
		ubyte checkSideSolidities(Solidity curSolidity, size_t index)
		{
			ubyte sides = 0;

			BlockId sideBlock0 = allBlocks[index + sideIndexOffsets[0]];
			sides |= (blockInfos[sideBlock0].solidity < curSolidity) << 0;

			BlockId sideBlock1 = allBlocks[index + sideIndexOffsets[1]];
			sides |= (blockInfos[sideBlock1].solidity < curSolidity) << 1;

			BlockId sideBlock2 = allBlocks[index + sideIndexOffsets[2]];
			sides |= (blockInfos[sideBlock2].solidity < curSolidity) << 2;

			BlockId sideBlock3 = allBlocks[index + sideIndexOffsets[3]];
			sides |= (blockInfos[sideBlock3].solidity < curSolidity) << 3;

			BlockId sideBlock4 = allBlocks[index + sideIndexOffsets[4]];
			sides |= (blockInfos[sideBlock4].solidity < curSolidity) << 4;

			BlockId sideBlock5 = allBlocks[index + sideIndexOffsets[5]];
			sides |= (blockInfos[sideBlock5].solidity < curSolidity) << 5;

			return sides;
		}

		// assumes that block to the side has lower solidity than current block
		// 0--3 // corner numbering of face verticies
		// |\ |
		// 1--2
		ubyte[4] calcCornerOcclusion(ushort blockIndex, ubyte side)
		{
			int index = blockIndex + sideIndexOffsets[side];

			Solidity solidityC = blockInfos[allBlocks[index]].solidity;

			bool solidityT = blockInfos[allBlocks[index + faceSideIndexOffset[side][0]]].solidity > solidityC;
			bool solidityL = blockInfos[allBlocks[index + faceSideIndexOffset[side][1]]].solidity > solidityC;
			bool solidityB = blockInfos[allBlocks[index + faceSideIndexOffset[side][2]]].solidity > solidityC;
			bool solidityR = blockInfos[allBlocks[index + faceSideIndexOffset[side][3]]].solidity > solidityC;

			ubyte[4] result; // 0-7

			result[0] = solidityT << 1 | solidityL << 2;
			if (!result[0])
				result[0] |= blockInfos[allBlocks[index + faceSideIndexOffset[side][4]]].solidity > solidityC;

			result[1] = solidityL << 1 | solidityB << 2;
			if (!result[1])
				result[1] |= blockInfos[allBlocks[index + faceSideIndexOffset[side][5]]].solidity > solidityC;

			result[2] = solidityB << 1 | solidityR << 2;
			if (!result[2])
				result[2] |= blockInfos[allBlocks[index + faceSideIndexOffset[side][6]]].solidity > solidityC;

			result[3] = solidityR << 1 | solidityT << 2;
			if (!result[3])
				result[3] |= blockInfos[allBlocks[index + faceSideIndexOffset[side][7]]].solidity > solidityC;

			return result;
		}

		void meshSide(CubeSide side, ubyte[4] cornerOcclusion, SideParams d)
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

		void meshBlock(BlockId blockId, ushort index, ubvec3 bpos, const BlockInfo* binfo)
		{
			ubyte sides = checkSideSolidities(binfo.solidity, index);

			if (sides != 0)
			{
				SideParams sideParams = SideParams(bpos, calcColor(index, binfo.color), &geometry[binfo.solidity]);
				//SideParams sideParams = SideParams(bpos, binfo.color, &geometry[binfo.solidity]);

				ubyte flag = 1;
				foreach(ubyte side; 0..6)
				{
					if (sides & flag)
					{
						ubyte[4] occlusion = calcCornerOcclusion(index, side);
						//ubyte[4] occlusion = [0,0,0,0];
						meshSide(cast(CubeSide)side, occlusion, sideParams);
					}
					flag <<= 1;
				}
			}
		}

		size_t index = extendedChunkIndex(1, 1, 1);

		foreach (ubyte y; 1..CHUNK_SIZE+1)
		{
			foreach (ubyte z; 1..CHUNK_SIZE+1)
			{
				foreach (ubyte x; 1..CHUNK_SIZE+1)
				{
					BlockId blockId = allBlocks.ptr[index];

					const BlockInfo* binfo = &blockInfos[blockId];
					if (binfo.isVisible)
					{
						ubvec3 bpos = ubvec3(x-1, y-1, z-1);
						meshBlock(blockId, cast(ushort)index, bpos, binfo);
					}

					++index;
				}
				index +=2;
			}
			index += EXTENDED_CHUNK_SIZE*2;
		}
	}
}
