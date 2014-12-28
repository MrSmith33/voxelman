/**
Copyright: Copyright (c) 2013-2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.chunkgen;

import std.concurrency : Tid, send, receive;
import std.stdio : writeln, writefln;
import std.variant : Variant;
import core.atomic : atomicLoad;
import core.exception : Throwable;

import dlib.math.vector : ivec3;
import anchovy.utils.noise.simplex;

import voxelman.block;
import voxelman.chunk;
import voxelman.config;


alias Generator = Generator2d;
//alias Generator = Generator2d3d;
//alias Generator = TestGeneratorSmallCubes;

struct ChunkGenResult
{
	ChunkData chunkData;
	ivec3 coord;
}

void chunkGenWorkerThread(Tid mainTid)
{
	try
	{
		shared(bool)* isRunning;
		bool isRunningLocal = true;
		receive( (shared(bool)* _isRunning){isRunning = _isRunning;} );

		while (atomicLoad(*isRunning) && isRunningLocal)
		{
			receive(
				(ivec3 coord){chunkGenWorker(coord, mainTid);},
				(Variant v){isRunningLocal = false;}
			);
		}
	}
	catch(Throwable t)
	{
		writeln(t, " from gen worker");
		throw t;
	}
}

// Gen single chunk
void chunkGenWorker(ivec3 coord, Tid mainThread)
{
	int wx = coord.x, wy = coord.y, wz = coord.z;

	ChunkData cd;
	cd.typeData = new BlockType[CHUNK_SIZE_CUBE];
	cd.uniform = true;

	Generator generator = Generator(coord * CHUNK_SIZE);
	generator.genPerChunkData();
	
	cd.typeData[0] = generator.generateBlock(0, 0, 0);
	BlockType type = cd.typeData[0];
	
	int bx, by, bz;
	foreach(i; 1..CHUNK_SIZE_CUBE)
	{
		bx = i & CHUNK_SIZE_BITS;
		by = (i / CHUNK_SIZE_SQR) & CHUNK_SIZE_BITS;
		bz = (i / CHUNK_SIZE) & CHUNK_SIZE_BITS;

		// Actual block gen
		cd.typeData[i] = generator.generateBlock(bx, by, bz);

		if(cd.uniform && cd.typeData[i] != type)
		{
			cd.uniform = false;
		}
	}

	if(cd.uniform)
	{
		//delete cd.typeData;
		cd.typeData = null;
		cd.uniformType = type;
	}

	//writefln("Chunk generated at %s uniform %s", chunk.coord, chunk.data.uniform);

	auto result = cast(immutable(ChunkGenResult)*)new ChunkGenResult(cd, coord);
	mainThread.send(result);
}

struct Generator2d3d
{
	ivec3 chunkOffset;

	private int[CHUNK_SIZE_SQR] heightMap;

	void genPerChunkData()
	{
		genPerChunkData2d(heightMap[], chunkOffset);
	}

	BlockType generateBlock(int x, int y, int z)
	{
		int height = heightMap[z * CHUNK_SIZE + x];
		int blockY = chunkOffset.y + y;
		if (blockY > height) return 1;

		float noise = Simplex.noise(cast(float)(chunkOffset.x+x)/42,
			cast(float)(chunkOffset.y+y)/42, cast(float)(chunkOffset.z+z)/42);
		if (noise < -0.1) return 1;

		if (blockY == height) return 2;
		else if (blockY > height - 10) return 3;
		else return 4;
	}
}

struct Generator2d
{
	ivec3 chunkOffset;

	private int[CHUNK_SIZE_SQR] heightMap;

	void genPerChunkData()
	{
		genPerChunkData2d(heightMap[], chunkOffset);
	}

	BlockType generateBlock(int x, int y, int z)
	{
		int height = heightMap[z * CHUNK_SIZE + x];
		int blockY = chunkOffset.y + y;
		if (blockY > height) return 1;
		if (blockY == height) return 2;
		else if (blockY > height - 10) return 3;
		else return 4;
	}
}

struct TestGeneratorSmallCubes
{
	ivec3 chunkOffset;
	void genPerChunkData(){}

	BlockType generateBlock(int x, int y, int z)
	{
		if (x % 2 == 0 && y % 2 == 0 && z % 2 == 0) return 2;
		else return 1;
	}
}

float noise2d(int x, int z)
{
	enum NUM_OCTAVES = 6;
	enum DIVIDER = 50; // bigger - smoother
	enum HEIGHT_MODIFIER = 4; // bigger - higher

	float noise = 0.0;
	foreach(i; 1..NUM_OCTAVES+1)
	{
		// [-1; 1]
		noise += Simplex.noise(cast(float)x/(DIVIDER*i), cast(float)z/(DIVIDER*i))*i*HEIGHT_MODIFIER;
	}

	return noise;
}

void genPerChunkData2d(int[] heightMap, ivec3 chunkOffset)
{
	foreach(i, ref elem; heightMap)
	{
		int cx = i & CHUNK_SIZE_BITS;
		int cz = (i / CHUNK_SIZE) & CHUNK_SIZE_BITS;
		elem = cast(int)noise2d(chunkOffset.x + cx, chunkOffset.z + cz);
	}
}