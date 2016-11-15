/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.gen.generators;

import voxelman.math : ivec3, svec2, svec3, SimplexNoise;
import voxelman.container.cache;

import voxelman.core.config;
import voxelman.world.storage.coordinates;
import voxelman.world.gen.utils;
import voxelman.world.gen.generator;

IGenerator[4] generators = [
	new GeneratorFlat,
	new Generator2d,
	new Generator2d3d,
	null
];


final class Generator2d3d : IGenerator
{
	ChunkGeneratorResult generateChunk(
		svec3 cwp,
		ref BlockId[CHUNK_SIZE_CUBE] blocks) const
	{
		svec2 cachePos = cwp.xz;
		ivec3 chunkOffset = ivec3(cwp) * CHUNK_SIZE;

		HeightmapChunkData* heightMap;
		if (auto val = heightmapCache.get(cachePos))
		{
			atomicOp!"+="(cache_hits, 1);
			heightMap = val;
		}
		else
		{
			atomicOp!"+="(cache_misses, 1);
			heightMap = heightmapCache.put(cachePos);
			heightMap.generate(chunkOffset);
		}

		if (chunkOffset.y > heightMap.maxHeight &&
			chunkOffset.y > 0)
		{
			return ChunkGeneratorResult(true, AIR);
		}
		else
		{
			foreach(i; 0..CHUNK_SIZE_CUBE)
			{
				ivec3 blockWorldPos;
				blockWorldPos.x = i & CHUNK_SIZE_BITS;
				blockWorldPos.y = (i / CHUNK_SIZE_SQR) & CHUNK_SIZE_BITS;
				blockWorldPos.z = (i / CHUNK_SIZE) & CHUNK_SIZE_BITS;
				int height = heightMap.heightMap[blockWorldPos.z * CHUNK_SIZE + blockWorldPos.x];
				blockWorldPos += chunkOffset;
				blocks[i] = generateBlock(blockWorldPos, height);
			}
			return ChunkGeneratorResult(false);
		}
	}

	static BlockId generateBlock(ivec3 blockWorldPos, int height) pure
	{
		enum NOISE_SCALE_3D = 42;
		enum NOISE_TRESHOLD_3D = -0.6;
		if (blockWorldPos.y > height) {
			if (blockWorldPos.y > 0)
				return AIR;
			else
				return WATER;
		}

		double noise3d = SimplexNoise.noise(cast(double)(blockWorldPos.x)/NOISE_SCALE_3D,
			cast(double)(blockWorldPos.y)/NOISE_SCALE_3D, cast(double)(blockWorldPos.z)/NOISE_SCALE_3D);
		if (noise3d < NOISE_TRESHOLD_3D) return AIR;

		if (height + 5 < 0)
		{
			if (height - blockWorldPos.y < 10) return SAND;
			else return STONE;
		}
		else
		{
			if (blockWorldPos.y == height) return GRASS;
			else if (blockWorldPos.y > height - 10) return DIRT;
			else return STONE;
		}
	}

	static Cache!(svec2, HeightmapChunkData, 16) heightmapCache;
}

shared size_t cache_hits;
shared size_t cache_misses;
import core.atomic;

final class Generator2d : IGenerator
{
	ChunkGeneratorResult generateChunk(
		svec3 cwp,
		ref BlockId[CHUNK_SIZE_CUBE] blocks) const
	{
		svec2 cachePos = cwp.xz;
		ivec3 chunkOffset = ivec3(cwp) * CHUNK_SIZE;

		HeightmapChunkData* heightMap;
		if (auto val = heightmapCache.get(cachePos))
		{
			atomicOp!"+="(cache_hits, 1);
			heightMap = val;
		}
		else
		{
			atomicOp!"+="(cache_misses, 1);
			heightMap = heightmapCache.put(cachePos);
			heightMap.generate(chunkOffset);
		}

		if (chunkOffset.y > heightMap.maxHeight &&
			chunkOffset.y > 0)
		{
			return ChunkGeneratorResult(true, AIR);
		}
		else
		{
			foreach(i; 0..CHUNK_SIZE_CUBE)
			{
				int bx = i & CHUNK_SIZE_BITS;
				int by = (i / CHUNK_SIZE_SQR) & CHUNK_SIZE_BITS;
				int bz = (i / CHUNK_SIZE) & CHUNK_SIZE_BITS;
				int blockY = chunkOffset.y + by;
				int height = heightMap.heightMap[bz * CHUNK_SIZE + bx];
				blocks[i] = generateBlock(blockY, height);
			}
			return ChunkGeneratorResult(false);
		}
	}

	static BlockId generateBlock(int blockY, int height) pure
	{
		if (blockY > height) {
			if (blockY > 0)
				return AIR;
			else
				return WATER;
		}

		if (height - 5 < 0)
		{
			if (height - blockY < 10) return SAND;
			else return STONE;
		}
		else
		{
			if (blockY == height) return GRASS;
			else if (blockY > height - 10) return DIRT;
			else return STONE;
		}
	}

	static Cache!(svec2, HeightmapChunkData, 16) heightmapCache;
}

final class GeneratorFlat : IGenerator
{
	ChunkGeneratorResult generateChunk(
		svec3 chunkOffset,
		ref BlockId[CHUNK_SIZE_CUBE] blocks) const
	{
		if (chunkOffset.y >= 0)
			return ChunkGeneratorResult(true, AIR);
		else
			return ChunkGeneratorResult(true, STONE);
	}
}
