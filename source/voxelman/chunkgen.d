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
	cd.typeData = new BlockType[chunkSizeCube];
	cd.uniform = true;

	Generator generator = Generator(coord);
	generator.genPerChunkData();
	
	cd.typeData[0] = generator.generateBlock(0, 0, 0);
	BlockType type = cd.typeData[0];
	
	int bx, by, bz;
	foreach(i; 1..chunkSizeCube)
	{
		bx = i & chunkSizeBits;
		by = (i / chunkSizeSqr) & chunkSizeBits;
		bz = (i / chunkSize) & chunkSizeBits;

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
	private int[chunkSizeSqr] heightMap;
	private int chunkXOffset;
	private int chunkYOffset;
	private int chunkZOffset;

	void genPerChunkData()
	{
		chunkXOffset = coord.x * chunkSize;
		chunkYOffset = coord.y * chunkSize;
		chunkZOffset = coord.z * chunkSize;
		foreach(i, ref elem; heightMap)
		{
			int cx = i & chunkSizeBits;
			int cz = (i / chunkSize) & chunkSizeBits;
			elem = cast(int)noise2d(chunkXOffset + cx, chunkZOffset + cz);
		}
	}

	BlockType generateBlock(int x, int y, int z)
	{
		int height = heightMap[z * chunkSize + x];
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
	enum numOctaves = 6;
	enum divider = 50; // bigger - smoother
	enum heightModifier = 4; // bigger - higher

	float noise = 0.0;
	foreach(i; 1..numOctaves+1)
	{
		// [-1; 1]
		noise += Simplex.noise(cast(float)x/(divider*i), cast(float)z/(divider*i))*i*heightModifier;
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