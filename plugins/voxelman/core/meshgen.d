/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.core.meshgen;

import std.experimental.logger;
import std.array : Appender;
import std.concurrency : Tid, send, receive;
import std.conv : to;
import std.variant : Variant;
import core.atomic : atomicLoad;
import core.exception : Throwable;

import dlib.math.vector : ivec3;

import voxelman.block.plugin;
import voxelman.block.utils;

import voxelman.core.config;
import voxelman.storage.chunk;
import voxelman.storage.coordinates;


struct MeshGenResult
{
	ubyte[] meshData;
	ChunkWorldPos position;
}

void meshWorkerThread(Tid mainTid, immutable(BlockInfo)[] blocks)
{
	try
	{
		shared(bool)* isRunning;
		bool isRunningLocal = true;
		receive( (shared(bool)* _isRunning){isRunning = _isRunning;} );

		while (atomicLoad(*isRunning) && isRunningLocal)
		{
			receive(
				(shared(Chunk)* chunk)
				{
					//infof("worker: mesh chunk %s", chunk.position);
					chunkMeshWorker(cast(Chunk*)chunk, (cast(Chunk*)chunk).adjacent, blocks, mainTid);
				},
				(shared(Chunk)* chunk, ushort[2] changedBlocksRange)
				{
					//chunkMeshWorker(cast(Chunk*)chunk, (cast(Chunk*)chunk).adjacent, blocks, mainTid);
				},
				(Variant v){isRunningLocal = false;}
			);
		}
	}
	catch(Throwable t)
	{
		error(t.to!string, " from mesh worker");
		throw t;
	}
}

void chunkMeshWorker(Chunk* chunk, Chunk*[6] adjacent, immutable(BlockInfo)[] blocks, Tid mainThread)
in
{
	assert(chunk);
	assert(!chunk.hasWriter);
	foreach(a; adjacent)
	{
		assert(a !is null);
		assert(!a.hasWriter);
	}
}
body
{
	Appender!(ubyte[]) appender;
	ubyte bx, by, bz;

	bool isVisibleBlock(uint id)
	{
		return blocks[id].isVisible;
	}

	bool isSolid(int tx, int ty, int tz)
	{
		ubyte x = cast(ubyte)tx;
		ubyte y = cast(ubyte)ty;
		ubyte z = cast(ubyte)tz;

		if(tx == -1) // west
			return blocks[ adjacent[Side.west].getBlockType(CHUNK_SIZE-1, y, z) ].isSolid;
		else if(tx == CHUNK_SIZE) // east
			return blocks[ adjacent[Side.east].getBlockType(0, y, z) ].isSolid;

		if(ty == -1) // bottom
		{
			return blocks[ adjacent[Side.bottom].getBlockType(x, CHUNK_SIZE-1, z) ].isSolid;
		}
		else if(ty == CHUNK_SIZE) // top
		{
			return blocks[ adjacent[Side.top].getBlockType(x, 0, z) ].isSolid;
		}

		if(tz == -1) // north
			return blocks[ adjacent[Side.north].getBlockType(x, y, CHUNK_SIZE-1) ].isSolid;
		else if(tz == CHUNK_SIZE) // south
			return blocks[ adjacent[Side.south].getBlockType(x, y, 0) ].isSolid;

		return blocks[ chunk.getBlockType(x, y, z) ].isSolid;
	}

	// Bit flags of sides to render
	ubyte sides = 0;
	// Offset to adjacent block
	byte[3] offset;

	if (!chunk.snapshot.blockData.uniform)
		assert(chunk.snapshot.blockData.blocks.length == CHUNK_SIZE_CUBE);

	if (chunk.snapshot.blockData.uniform)
	{
		BlockId id = chunk.snapshot.blockData.uniformType;
		auto meshHandler = blocks[id].meshHandler;
		auto color = blocks[id].color;
		foreach (uint index; 0..CHUNK_SIZE_CUBE)
		{
			bx = index & CHUNK_SIZE_BITS;
			by = (index / CHUNK_SIZE_SQR) & CHUNK_SIZE_BITS;
			bz = (index / CHUNK_SIZE) & CHUNK_SIZE_BITS;
			sides = 0;

			foreach(ubyte side; 0..6)
			{
				offset = sideOffsets[cast(Side)side];

				if(!isSolid(bx+offset[0], by+offset[1], bz+offset[2]))
				{
					sides |= 2^^(side);
				}
			}
			meshHandler(appender, color, bx, by, bz, sides);
		} // foreach
	}
	else
	foreach (uint index, ubyte val; chunk.snapshot.blockData.blocks)
	{
		if (blocks[val].isVisible)
		{
			bx = index & CHUNK_SIZE_BITS;
			by = (index / CHUNK_SIZE_SQR) & CHUNK_SIZE_BITS;
			bz = (index / CHUNK_SIZE) & CHUNK_SIZE_BITS;
			sides = 0;

			foreach(ubyte side; 0..6)
			{
				offset = sideOffsets[cast(Side)side];

				if(!isSolid(bx+offset[0], by+offset[1], bz+offset[2]))
				{
					sides |= 2^^(side);
				}
			}

			blocks[val].meshHandler(appender, blocks[val].color, bx, by, bz, sides);
		} // if(val != 0)
	} // foreach

	auto result = cast(immutable(MeshGenResult)*)
		new MeshGenResult(cast(ubyte[])appender.data, chunk.position);
	mainThread.send(result);
}
