/**
Copyright: Copyright (c) 2013-2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.meshgen;

import std.array : Appender;
import std.concurrency : Tid, send, receive;
import std.conv : to;
import std.stdio : writeln;
import std.variant : Variant;
import core.atomic : atomicLoad;
import core.exception : Throwable;

import voxelman.block;
import voxelman.chunk;
import voxelman.chunkman;


struct MeshGenResult
{
	ubyte[] meshData;
	ChunkCoord coord;
}

void meshWorkerThread(Tid mainTid, shared(ChunkMan)* cman)
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
					chunkMeshWorker(cast(Chunk*)chunk, (cast(Chunk*)chunk).adjacent, cast(ChunkMan*)cman, mainTid);
				},
				(Variant v){isRunningLocal = false;}
			);
		}
	}
	catch(Throwable t)
	{
		writeln(t, " from mesh worker");
		throw t;
	}
}

void chunkMeshWorker(Chunk* chunk, Chunk*[6] adjacent, ChunkMan* cman, Tid mainThread)
in
{
	assert(chunk);
	assert(!chunk.hasWriter);
	assert(cman);
	foreach(a; adjacent)
	{
		assert(a != Chunk.unknownChunk);
		assert(!a.hasWriter);
		assert(a.isLoaded);
	}
}
body
{
	Appender!(ubyte[]) appender;
	ubyte bx, by, bz;

	IBlock[] blockTypes = cman.blockTypes;

	bool isVisibleBlock(uint id)
	{
		return cman.blockTypes[id].isVisible;
	}
	
	bool getTransparency(int tx, int ty, int tz, ubyte side)
	{
		ubyte x = cast(ubyte)tx;
		ubyte y = cast(ubyte)ty;
		ubyte z = cast(ubyte)tz;

		if(tx == -1) // west
			return blockTypes[ adjacent[Side.west].getBlockType(chunkSize-1, y, z) ].isSideTransparent(side);
		else if(tx == chunkSize) // east
			return blockTypes[ adjacent[Side.east].getBlockType(0, y, z) ].isSideTransparent(side);

		if(ty == -1) // bottom
		{
			assert(side == Side.top, to!string(side));
			return blockTypes[ adjacent[Side.bottom].getBlockType(x, chunkSize-1, z) ].isSideTransparent(side);
		}
		else if(ty == chunkSize) // top
		{
			return blockTypes[ adjacent[Side.top].getBlockType(x, 0, z) ].isSideTransparent(side);
		}

		if(tz == -1) // north
			return blockTypes[ adjacent[Side.north].getBlockType(x, y, chunkSize-1) ].isSideTransparent(side);
		else if(tz == chunkSize) // south
			return blockTypes[ adjacent[Side.south].getBlockType(x, y, 0) ].isSideTransparent(side);
		
		return blockTypes[ chunk.getBlockType(x, y, z) ].isSideTransparent(side);
	}
	
	// Bit flags of sides to render
	ubyte sides = 0;
	// Num of sides to render
	ubyte sidenum = 0;
	// Offset to adjacent block
	byte[3] offset;

	if (chunk.data.uniform)
	{
		foreach (uint index; 0..chunkSizeCube)
		{
			bx = index & chunkSizeBits;
			by = (index / chunkSizeSqr) & chunkSizeBits;
			bz = (index / chunkSize) & chunkSizeBits;
			sides = 0;
			sidenum = 0;
			
			foreach(ubyte side; 0..6)
			{
				offset = sideOffsets[side];
				
				if(getTransparency(bx+offset[0], by+offset[1], bz+offset[2], oppSide[side]))
				{	
					sides |= 2^^(side);
					++sidenum;
				}
			}
			
			appender ~= cman.blockTypes[chunk.data.uniformType]
							.getMesh(bx, by, bz, sides, sidenum);
		} // foreach
	}
	else
	foreach (uint index, ref ubyte val; chunk.data.typeData)
	{
		if (isVisibleBlock(val))
		{	
			bx = index & chunkSizeBits;
			by = (index / chunkSizeSqr) & chunkSizeBits;
			bz = (index / chunkSize) & chunkSizeBits;
			sides = 0;
			sidenum = 0;
			
			foreach(ubyte side; 0..6)
			{
				offset = sideOffsets[side];
				
				if(getTransparency(bx+offset[0], by+offset[1], bz+offset[2], oppSide[side]))
				{	
					sides |= 2^^(side);
					++sidenum;
				}
			}
			
			appender ~= cman.blockTypes[val].getMesh(bx, by, bz, sides, sidenum);
		} // if(val != 0)
	} // foreach

	auto result = cast(immutable(MeshGenResult)*)
		new MeshGenResult(cast(ubyte[])appender.data, chunk.coord);
	mainThread.send(result);
}