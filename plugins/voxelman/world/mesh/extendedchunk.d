/**
Copyright: Copyright (c) 2017-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.mesh.extendedchunk;

import voxelman.math;
import voxelman.geometry;
import voxelman.core.config;
import voxelman.world.mesh.utils;
import voxelman.world.storage;

void setExtendedArray(
	BlockId[] dest,
	ivec3 destPos,
	ChunkLayerItem source,
	Box sourceBox)
{
	if (source.isUniform)
		setSubArray3d(dest, EXTENDED_SIZE_VECTOR, Box(destPos, sourceBox.size), source.getUniform!BlockId);
	else
		setSubArray3d(dest, EXTENDED_SIZE_VECTOR, destPos, source.getArray!BlockId, CHUNK_SIZE_VECTOR, sourceBox);
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
