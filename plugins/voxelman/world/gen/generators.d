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

IGenerator[2] generators = [
	new Generator2d,
	new GeneratorFlat,
];


struct Generator2d3d
{
	ivec3 chunkOffset;

	private HeightmapChunkData heightMap;

	void genPerChunkData()
	{
		heightMap.generate(chunkOffset);
	}

	BlockId generateBlock(int x, int y, int z)
	{
		enum NOISE_SCALE_3D = 42;
		enum NOISE_TRESHOLD_3D = -0.6;
		int height = heightMap.heightMap[z * CHUNK_SIZE + x];
		int blockY = chunkOffset.y + y;
		if (blockY > height) {
			if (blockY > 0)
				return AIR;
			else
				return WATER;
		}

		double noise3d = SimplexNoise.noise(cast(double)(chunkOffset.x+x)/NOISE_SCALE_3D,
			cast(double)(chunkOffset.y+y)/NOISE_SCALE_3D, cast(double)(chunkOffset.z+z)/NOISE_SCALE_3D);
		if (noise3d < NOISE_TRESHOLD_3D) return AIR;

		if (height + 5 < 0)
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

	BlockId generateBlock(int blockY, int height) const
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

struct TestGeneratorSmallCubes2
{
	ivec3 chunkOffset;
	void genPerChunkData(){}

	bool uniformChunkGen(out BlockId uniformBlockId) {
		return false;
	}

	BlockId generateBlock(int x, int y, int z)
	{
		if (x % 4 == 0 && y % 4 == 0 && z % 4 == 0) return GRASS;
		else return AIR;
	}
}

struct TestGeneratorSmallCubes3
{
	enum cubesSizes = 4;
	enum cubeOffsets = 16;
	ivec3 chunkOffset;
	void genPerChunkData(){}

	bool uniformChunkGen(out BlockId uniformBlockId) {
		return false;
	}

	BlockId generateBlock(int x, int y, int z)
	{
		if (x % cubeOffsets < cubesSizes &&
			y % cubeOffsets < cubesSizes &&
			z % cubeOffsets < cubesSizes) return WATER;
		else return AIR;
	}
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
