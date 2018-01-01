/**
Copyright: Copyright (c) 2013-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.gen.utils;

import voxelman.log;
import voxelman.math : ivec3, SimplexNoise;

import voxelman.world.block;
import voxelman.core.config;
import voxelman.thread.worker;
import voxelman.world.storage.chunk;
import voxelman.world.storage.coordinates;

enum AIR = 1;
enum GRASS = 2;
enum DIRT = 3;
enum STONE = 4;
enum SAND = 5;
enum WATER = 6;
enum LAVA = 7;
enum SNOW = 8;

struct ChunkGeneratorResult
{
	bool uniform;
	BlockId uniformBlockId;
}

double noise2d(int x, int z)
{
	enum NUM_OCTAVES = 8;
	enum DIVIDER = 50; // bigger - smoother
	enum HEIGHT_MODIFIER = 4; // bigger - higher

	double noise = 0.0;
	foreach(i; 1..NUM_OCTAVES+1)
	{
		// [-1; 1]
		noise += SimplexNoise.noise(cast(double)x/(DIVIDER*i), cast(double)z/(DIVIDER*i))*i*HEIGHT_MODIFIER;
	}

	return noise;
}

struct HeightmapChunkData
{
	int[CHUNK_SIZE_SQR] heightMap = void;
	int minHeight = int.max;
	int maxHeight = int.min;

	void generate(ivec3 chunkOffset)
	{
		foreach(i, ref elem; heightMap)
		{
			int cx = i & CHUNK_SIZE_BITS;
			int cz = (i / CHUNK_SIZE) & CHUNK_SIZE_BITS;
			elem = cast(int)noise2d(chunkOffset.x + cx, chunkOffset.z + cz);
			if (elem > maxHeight)
				maxHeight = elem;
			if (elem < minHeight)
				minHeight = elem;
		}
	}
}
