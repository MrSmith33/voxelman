/**
Copyright: Copyright (c) 2013-2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.chunkgen;

import std.concurrency : Tid, send, receive;
import std.stdio : writeln;
import std.variant : Variant;
import core.atomic : atomicLoad;
import core.exception : Throwable;

import anchovy.utils.noise.simplex;

import voxelman.block;
import voxelman.chunk;


alias Generator = Generator2d;

struct ChunkGenResult
{
	ChunkData chunkData;
	ChunkCoord coord;
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
				(ChunkCoord coord){chunkGenWorker(coord, mainTid);},
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
void chunkGenWorker(ChunkCoord coord, Tid mainThread)
{
	int wx = coord.x, wy = coord.y, wz = coord.z;

	ChunkData cd;
	cd.typeData = new BlockType[CHUNK_SIZE_CUBE];
	cd.uniform = true;

	Generator generator = Generator(coord);
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

struct Generator2d
{
	ChunkCoord coord;
	private int[CHUNK_SIZE_SQR] heightMap;
	private int chunkXOffset;
	private int chunkYOffset;
	private int chunkZOffset;

	void genPerChunkData()
	{
		chunkXOffset = coord.x * CHUNK_SIZE;
		chunkYOffset = coord.y * CHUNK_SIZE;
		chunkZOffset = coord.z * CHUNK_SIZE;
		foreach(i, ref elem; heightMap)
		{
			int cx = i & CHUNK_SIZE_BITS;
			int cz = (i / CHUNK_SIZE) & CHUNK_SIZE_BITS;
			elem = cast(int)noise2d(chunkXOffset + cx, chunkZOffset + cz);
		}
	}

	BlockType generateBlock(int x, int y, int z)
	{
		int height = heightMap[z * CHUNK_SIZE + x];
		int blockY = chunkYOffset + y;
		if (blockY > height) return 1;

		float noise = Simplex.noise(cast(float)(chunkXOffset+x)/42,
			cast(float)(chunkYOffset+y)/42, cast(float)(chunkZOffset+z)/42);
		if (noise < -0.1) return 1;

		if (blockY == height) return 2;
		else if (blockY > height - 10) return 3;
		else return 4;
	}
}

struct TestGenerator
{
	ChunkCoord coord;
	void genPerChunkData(){}

	BlockType generateBlock(int x, int y, int z)
	{
		return getBlockTest(x + coord.x, y + coord.y, z + coord.z);
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

// Gen single block
BlockType getBlock2d( int x, int y, int z)
{
	float noise = noise2d(x, z);

	if (noise >= y) return 2;
	else return 1;
}

BlockType getBlock3d( int x, int y, int z)
{
	// [-1; 1]
	float noise = Simplex.noise(cast(float)x/42, cast(float)y/42, cast(float)z/42);
	if (noise > 0.5) return 2;
	else return 1;
}

BlockType getBlock2d3d( int x, int y, int z)
{
	float noise = noise2d(x, z);

	if (noise >= y)
	{
		// [-1; 1]
		float noise3d = Simplex.noise(cast(float)x/42, cast(float)y/42, cast(float)z/42);
		if (noise3d > -0.1) return 2;
		else return 1;
	}
	else return 1;
}

BlockType getBlockTest( int x, int y, int z)
{
	if (x % 4 > 1 && y % 4 > 1 && z % 4 > 1) return 2;
	else return 1;
}