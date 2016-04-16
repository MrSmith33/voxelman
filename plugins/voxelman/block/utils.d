/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.block.utils;

import std.array : Appender;
import dlib.math.vector : vec3, ivec3;

import voxelman.core.config;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.chunk;
import voxelman.utils.mapping;

enum Side : ubyte
{
	north	= 0,
	south	= 1,

	east	= 2,
	west	= 3,

	top		= 4,
	bottom	= 5,
}

enum SideMask : ubyte
{
	north	= 1,
	south	= 2,

	east	= 4,
	west	= 8,

	top		= 16,
	bottom	= 32,
}

immutable ubyte[6] oppSide = [1, 0, 3, 2, 5, 4];

immutable byte[3][6] sideOffsets = [
	[ 0, 0,-1],
	[ 0, 0, 1],
	[ 1, 0, 0],
	[-1, 0, 0],
	[ 0, 1, 0],
	[ 0,-1, 0],
];

Side sideFromNormal(ivec3 normal)
{
	if (normal.x == 1)
		return Side.east;
	else if (normal.x == -1)
		return Side.west;

	if (normal.y == 1)
		return Side.top;
	else if (normal.y == -1)
		return Side.bottom;

	if (normal.z == 1)
		return Side.south;
	else if (normal.z == -1)
		return Side.north;

	return Side.north;
}

void makeNullMesh(ref Appender!(ubyte[]), ubyte[3], ubyte, ubyte, ubyte, ubyte) {}

void makeColoredBlockMesh(ref Appender!(ubyte[]) output,
	ubyte[3] color, ubyte bx, ubyte by, ubyte bz, ubyte sides)
{
	import std.random;
	static immutable(float)[] shadowMultipliers = [
		0.7, 0.75, 0.6, 0.5, 0.85, 0.4,
	];

	auto index = BlockChunkIndex(bx, by, bz).index;
	auto rnd = Xorshift32(index);
	float randomTint = uniform(0.90f, 1.0f, rnd);

	foreach(ubyte i; 0..6)
	{
		if (sides & (2^^i))
		{
			for (size_t v = 0; v!=18; v+=3)
			{
				output ~= cast(ubyte)(faces[18*i+v] + bx);
				output ~= cast(ubyte)(faces[18*i+v+1] + by);
				output ~= cast(ubyte)(faces[18*i+v+2] + bz);
				output ~= cast(ubyte)0;
				output ~= cast(ubyte)(shadowMultipliers[i] * color[0] * randomTint);
				output ~= cast(ubyte)(shadowMultipliers[i] * color[1] * randomTint);
				output ~= cast(ubyte)(shadowMultipliers[i] * color[2] * randomTint);
				output ~= cast(ubyte)0;
			} // for v
		} // if
	} // for i
}

alias BlockUpdateHandler = void delegate(BlockWorldPos bwp);
alias Meshhandler = void function(ref Appender!(ubyte[]) output,
	ubyte[3] color, ubyte bx, ubyte by, ubyte bz, ubyte sides);

struct BlockInfo
{
	string name;
	Meshhandler meshHandler = &makeNullMesh;
	ubyte[3] color;
	bool isVisible = true;
	bool isSolid = true;
	size_t id;
}

/// Returned when registering block.
/// Use this to set block properties.
struct BlockInfoSetter
{
	private Mapping!(BlockInfo)* mapping;
	private size_t blockId;
	private ref BlockInfo info() {return (*mapping)[blockId]; }

	ref BlockInfoSetter meshHandler(Meshhandler val) { info.meshHandler = val; return this; }
	ref BlockInfoSetter color(ubyte[3] color ...) { info.color = color; return this; }
	ref BlockInfoSetter colorHex(uint hex) { info.color = [(hex>>16)&0xFF,(hex>>8)&0xFF,hex&0xFF]; return this; }
	ref BlockInfoSetter isVisible(bool val) { info.isVisible = val; return this; }
	ref BlockInfoSetter isSolid(bool val) { info.isSolid = val; return this; }
}

ubyte calcChunkSideMetadata(ChunkLayerSnap blockLayer, immutable(BlockInfo)[] blockInfos)
{
	if (blockLayer.type == StorageType.uniform)
	{
		return calcChunkSideMetadata(blockLayer.getUniform!BlockId, blockInfos);
	}
	else if (blockLayer.type == StorageType.fullArray)
	{
		BlockId[] blocks = blockLayer.getArray!BlockId;
		return calcChunkSideMetadata(blocks, blockInfos);
	}
	else
		assert(false);
}

bool isChunkSideSolid(const ubyte metadata, const Side side)
{
	if (metadata & 0b1_000000)
		return !!(metadata & 1<<side);
	else
		return true;
}

ubyte calcChunkSideMetadata(BlockId uniformBlock, immutable(BlockInfo)[] blockInfos)
{
	bool isSolid = blockInfos[uniformBlock].isSolid;
	// 1 = metadata is present, 6 bits = transparency of 6 chunk sides
	return isSolid ? 0b1_111111 : 0b1_000000;
}

ubyte calcChunkSideMetadata(BlockId[] blocks, immutable(BlockInfo)[] blockInfos)
{
	ubyte flags = 0b1_111111;
	foreach(index; 0..CHUNK_SIZE_SQR) // bottom
	{
		if (!blockInfos[blocks[index]].isSolid)
		{
			flags ^= SideMask.bottom;
			break;
		}
	}

	outer_north:
	foreach(y; 0..CHUNK_SIZE)
	foreach(x; 0..CHUNK_SIZE)
	{
		size_t index = y*CHUNK_SIZE_SQR | x; // north
		if (!blockInfos[blocks[index]].isSolid)
		{
			flags ^= SideMask.north;
			break outer_north;
		}
	}

	outer_south:
	foreach(y; 0..CHUNK_SIZE)
	foreach(x; 0..CHUNK_SIZE)
	{
		size_t index = (CHUNK_SIZE-1) * CHUNK_SIZE | y*CHUNK_SIZE_SQR | x; // south
		if (!blockInfos[blocks[index]].isSolid)
		{
			flags ^= SideMask.south;
			break outer_south;
		}
	}

	outer_east:
	foreach(y; 0..CHUNK_SIZE)
	foreach(z; 0..CHUNK_SIZE)
	{
		size_t index = z * CHUNK_SIZE | y*CHUNK_SIZE_SQR | (CHUNK_SIZE-1); // east
		if (!blockInfos[blocks[index]].isSolid)
		{
			flags ^= SideMask.east;
			break outer_east;
		}
	}

	outer_west:
	foreach(y; 0..CHUNK_SIZE)
	foreach(z; 0..CHUNK_SIZE)
	{
		size_t index = z * CHUNK_SIZE | y*CHUNK_SIZE_SQR; // west
		if (!blockInfos[blocks[index]].isSolid)
		{
			flags ^= SideMask.west;
			break outer_west;
		}
	}

	foreach(index; CHUNK_SIZE_CUBE-CHUNK_SIZE_SQR..CHUNK_SIZE_CUBE) // top
	{
		if (!blockInfos[blocks[index]].isSolid)
		{
			flags ^= SideMask.top;
			break;
		}
	}

	return flags;
}


/*
void iterateSides()
{
	foreach(index; 0..CHUNK_SIZE_SQR) // bottom

	{// north
		ubyte z = 0;
		foreach(y; 0..CHUNK_SIZE)
			foreach(x; 0..CHUNK_SIZE)
				index = z * CHUNK_SIZE | y*CHUNK_SIZE_SQR | x;
	}

	{// south
		ubyte z = CHUNK_SIZE-1;
		foreach(y; 0..CHUNK_SIZE)
			foreach(x; 0..CHUNK_SIZE)
				index = z * CHUNK_SIZE | y*CHUNK_SIZE_SQR | x;
	}

	{// east
		ubyte x = CHUNK_SIZE-1;
		foreach(y; 0..CHUNK_SIZE)
			foreach(z; 0..CHUNK_SIZE)
				index = z * CHUNK_SIZE | y*CHUNK_SIZE_SQR | x;
	}

	{// west
		ubyte x = 0;
		foreach(y; 0..CHUNK_SIZE)
			foreach(z; 0..CHUNK_SIZE)
				index = z * CHUNK_SIZE | y*CHUNK_SIZE_SQR | x;
	}

	foreach(index; CHUNK_SIZE_CUBE-CHUNK_SIZE_SQR..CHUNK_SIZE_CUBE) // top
}
*/

// mesh for single block
immutable ubyte[18 * 6] faces =
[
	0, 0, 0, // triangle 1 : begin // north
	1, 0, 0,
	1, 1, 0, // triangle 1 : end
	0, 0, 0, // triangle 2 : begin
	1, 1, 0,
	0, 1, 0, // triangle 2 : end

	1, 0, 1, // south
	0, 0, 1,
	0, 1, 1,
	1, 0, 1,
	0, 1, 1,
	1, 1, 1,

	1, 0, 0, // east
	1, 0, 1,
	1, 1, 1,
	1, 0, 0,
	1, 1, 1,
	1, 1, 0,

	0, 0, 1, // west
	0, 0, 0,
	0, 1, 0,
	0, 0, 1,
	0, 1, 0,
	0, 1, 1,

	1, 1, 1, // top
	0, 1, 1,
	0, 1, 0,
	1, 1, 1,
	0, 1, 0,
	1, 1, 0,

	0, 0, 1, // bottom
	1, 0, 1,
	1, 0, 0,
	0, 0, 1,
	1, 0, 0,
	0, 0, 0,
];
