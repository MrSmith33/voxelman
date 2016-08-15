/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.gen.generators;

import voxelman.math : ivec3;

import anchovy.simplex;
import voxelman.core.config;
import voxelman.world.storage.coordinates;
import voxelman.world.gen.utils;

GenDelegate[5] generators = [
	&genChunk!GeneratorFlat,
	&genChunk!Generator2d,
	&genChunk!Generator2d3d,
	&genChunk!TestGeneratorSmallCubes2,
	&genChunk!TestGeneratorSmallCubes3
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

		float noise3d = Simplex.noise(cast(float)(chunkOffset.x+x)/NOISE_SCALE_3D,
			cast(float)(chunkOffset.y+y)/NOISE_SCALE_3D, cast(float)(chunkOffset.z+z)/NOISE_SCALE_3D);
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

struct Generator2d
{
	ivec3 chunkOffset;
	HeightmapChunkData heightMap;

	void genPerChunkData()
	{
		heightMap.generate(chunkOffset);
	}

	BlockId generateBlock(int x, int y, int z)
	{
		int height = heightMap.heightMap[z * CHUNK_SIZE + x];
		int blockY = chunkOffset.y + y;
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
}

struct TestGeneratorSmallCubes2
{
	ivec3 chunkOffset;
	void genPerChunkData(){}

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

	BlockId generateBlock(int x, int y, int z)
	{
		if (x % cubeOffsets < cubesSizes &&
			y % cubeOffsets < cubesSizes &&
			z % cubeOffsets < cubesSizes) return WATER;
		else return AIR;
	}
}

struct GeneratorFlat
{
	ivec3 chunkOffset;
	HeightmapChunkData heightMap;

	void genPerChunkData()
	{
		heightMap.minHeight = heightMap.maxHeight = 0;
	}

	BlockId generateBlock(int x, int y, int z)
	{
		int blockY = chunkOffset.y + y;
		if (blockY >= 0)
			return AIR;
		else
			return STONE;
	}
}
