/**
Copyright: Copyright (c) 2013-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.meshgen;

import std.experimental.logger;
import std.array : Appender;
import std.concurrency : Tid, send, receive;
import std.conv : to;
import std.variant : Variant;
import core.atomic : atomicLoad;
import core.exception : Throwable;

import dlib.math.vector : ivec3;

import voxelman.block;
import voxelman.storage.chunk;
import voxelman.config;


struct MeshGenResult
{
	ubyte[] meshData;
	ivec3 coord;
}

void meshWorkerThread(Tid mainTid, immutable(Block*)[] blocks)
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
					//infof("worker: mesh chunk %s", chunk.coord);
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

void chunkMeshWorker(Chunk* chunk, Chunk*[6] adjacent, immutable(Block*)[] blocks, Tid mainThread)
in
{
	assert(chunk);
	assert(!chunk.hasWriter);
	foreach(a; adjacent)
	{
		assert(a !is null);
		assert(!a.hasWriter);
		assert(a.isLoaded);
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

	bool getTransparency(int tx, int ty, int tz, Side side)
	{
		ubyte x = cast(ubyte)tx;
		ubyte y = cast(ubyte)ty;
		ubyte z = cast(ubyte)tz;

		if(tx == -1) // west
			return blocks[ adjacent[Side.west].getBlockType(CHUNK_SIZE-1, y, z) ].isSideTransparent(side);
		else if(tx == CHUNK_SIZE) // east
			return blocks[ adjacent[Side.east].getBlockType(0, y, z) ].isSideTransparent(side);

		if(ty == -1) // bottom
		{
			assert(side == Side.top, to!string(side));
			return blocks[ adjacent[Side.bottom].getBlockType(x, CHUNK_SIZE-1, z) ].isSideTransparent(side);
		}
		else if(ty == CHUNK_SIZE) // top
		{
			return blocks[ adjacent[Side.top].getBlockType(x, 0, z) ].isSideTransparent(side);
		}

		if(tz == -1) // north
			return blocks[ adjacent[Side.north].getBlockType(x, y, CHUNK_SIZE-1) ].isSideTransparent(side);
		else if(tz == CHUNK_SIZE) // south
			return blocks[ adjacent[Side.south].getBlockType(x, y, 0) ].isSideTransparent(side);

		return blocks[ chunk.getBlockType(x, y, z) ].isSideTransparent(side);
	}

	// Bit flags of sides to render
	ubyte sides = 0;
	// Num of sides to render
	ubyte sidenum = 0;
	// Offset to adjacent block
	byte[3] offset;

	if (chunk.snapshot.blockData.uniform)
	{
		foreach (uint index; 0..CHUNK_SIZE_CUBE)
		{
			bx = index & CHUNK_SIZE_BITS;
			by = (index / CHUNK_SIZE_SQR) & CHUNK_SIZE_BITS;
			bz = (index / CHUNK_SIZE) & CHUNK_SIZE_BITS;
			sides = 0;
			sidenum = 0;

			foreach(ubyte side; 0..6)
			{
				offset = sideOffsets[cast(Side)side];

				if(getTransparency(bx+offset[0], by+offset[1], bz+offset[2], cast(Side)oppSide[side]))
				{
					sides |= 2^^(side);
					++sidenum;
				}
			}

			appender ~= blocks[chunk.snapshot.blockData.uniformType]
							.mesh(bx, by, bz, sides, sidenum);
		} // foreach
	}
	else
	foreach (uint index, ref ubyte val; chunk.snapshot.blockData.blocks)
	{
		if (isVisibleBlock(val))
		{
			bx = index & CHUNK_SIZE_BITS;
			by = (index / CHUNK_SIZE_SQR) & CHUNK_SIZE_BITS;
			bz = (index / CHUNK_SIZE) & CHUNK_SIZE_BITS;
			sides = 0;
			sidenum = 0;

			foreach(ubyte side; 0..6)
			{
				offset = sideOffsets[cast(Side)side];

				if(getTransparency(bx+offset[0], by+offset[1], bz+offset[2], cast(Side)oppSide[side]))
				{
					sides |= 2^^(side);
					++sidenum;
				}
			}

			appender ~= blocks[val].mesh(bx, by, bz, sides, sidenum);
		} // if(val != 0)
	} // foreach

	auto result = cast(immutable(MeshGenResult)*)
		new MeshGenResult(cast(ubyte[])appender.data, chunk.coord);
	mainThread.send(result);
}
