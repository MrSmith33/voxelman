/**
Copyright: Copyright (c) 2015-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.coordinates;

import voxelman.core.config;
import voxelman.world.storage.utils;
import voxelman.math;
public import voxelman.core.config : DimensionId;

ivec3 blockToChunkPosition(ivec3 blockPos)
{
	return ivec3(
		floor(cast(float)blockPos.x / CHUNK_SIZE),
		floor(cast(float)blockPos.y / CHUNK_SIZE),
		floor(cast(float)blockPos.z / CHUNK_SIZE));
}

ivec3 chunkToBlockPosition(ivec3 cp)
{
	return ivec3(cp.x*CHUNK_SIZE, cp.y*CHUNK_SIZE, cp.z * CHUNK_SIZE);
}

ivec3 chunkStartBlockPos(ivec3 worldBlockPos) {
	return ivec3(
		floor(cast(float)worldBlockPos.x / CHUNK_SIZE) * CHUNK_SIZE,
		floor(cast(float)worldBlockPos.y / CHUNK_SIZE) * CHUNK_SIZE,
		floor(cast(float)worldBlockPos.z / CHUNK_SIZE) * CHUNK_SIZE);
}

struct ClientDimPos
{
	vec3 pos = vec3(0,0,0);
	vec2 heading = vec2(0,0);
}

struct BlockChunkIndex
{
	this(BlockChunkPos blockChunkPos)
	{
		index = cast(ushort)(blockChunkPos.x +
			blockChunkPos.y * CHUNK_SIZE_SQR +
			blockChunkPos.z * CHUNK_SIZE);
	}

	this(BlockWorldPos blockWorldPos)
	{
		this(BlockChunkPos(blockWorldPos));
	}

	this(ushort index)
	{
		this.index = index;
	}

	this(int x, int y, int z)
	{
		index = cast(ushort)(x + y * CHUNK_SIZE_SQR + z * CHUNK_SIZE);
	}

	this(T)(Vector!(T, 3) pos)
	{
		index = cast(ushort)(pos.x + pos.y * CHUNK_SIZE_SQR + pos.z * CHUNK_SIZE);
	}

	ushort index;

	size_t getIndex() @property { return index; }
	alias getIndex this;
}

// Position of block in world space. -int.max..int.max
struct BlockWorldPos
{
	this(ChunkWorldPos cwp, ushort index) {
		ubyte bx = index & CHUNK_SIZE_BITS;
		ubyte by = index / CHUNK_SIZE_SQR;
		ubyte bz = (index / CHUNK_SIZE) & CHUNK_SIZE_BITS;
		vector = ivec4(
			cwp.x * CHUNK_SIZE + bx,
			cwp.y * CHUNK_SIZE + by,
			cwp.z * CHUNK_SIZE + bz,
			cwp.w);
	}

	this(ivec3 blockWorldPos, int dim)
	{
		vector = ivec4(blockWorldPos.x, blockWorldPos.y, blockWorldPos.z, dim);
	}

	this(ivec4 blockWorldPos)
	{
		vector = blockWorldPos;
	}

	this(vec3 blockWorldPos, int dim)
	{
		vector = ivec4(blockWorldPos.x, blockWorldPos.y, blockWorldPos.z, dim);
	}

	this(int x, int y, int z, int dim)
	{
		vector = ivec4(x, y, z, dim);
	}

	this(int[4] pos)
	{
		vector = ivec4(pos[0], pos[1], pos[2], pos[3]);
	}

	ivec4 vector;
	auto opDispatch(string s)()
	{
		return mixin("vector." ~ s);
	}

	void toString()(scope void delegate(const(char)[]) sink)
	{
		import std.format : formattedWrite;
		sink.formattedWrite("bwp(%(%s %))", vector.arrayof);
	}
}

static assert(!is(typeof({
	ChunkRegionPos vector = ChunkRegionPos(BlockWorldPos());
	})));
static assert(!is(typeof({
	ChunkRegionPos vector = BlockWorldPos();
	})));
static assert(!is(typeof({
	BlockWorldPos vector = BlockWorldPos(BlockWorldPos());
	})));

// Position of block in chunk space. 0..ChunkSize
struct BlockChunkPos
{
	this(BlockWorldPos blockWorldPos)
	{
		vector.x = blockWorldPos.x % CHUNK_SIZE;
		vector.y = blockWorldPos.y % CHUNK_SIZE;
		vector.z = blockWorldPos.z % CHUNK_SIZE;
		if (vector.x < 0) vector.x += CHUNK_SIZE;
		if (vector.y < 0) vector.y += CHUNK_SIZE;
		if (vector.z < 0) vector.z += CHUNK_SIZE;
	}

	this(BlockChunkIndex blockIndex)
	{
		this(blockIndex.index);
	}

	this(ushort blockIndex)
	{
		vector.x = blockIndex & CHUNK_SIZE_BITS;
		vector.y = blockIndex / CHUNK_SIZE_SQR;
		vector.z = (blockIndex / CHUNK_SIZE) & CHUNK_SIZE_BITS;
	}

	this(uvec3 blockChunkPos)
	{
		vector = blockChunkPos;
	}

	ivec3 vector;
	auto opDispatch(string s)()
	{
		return mixin("vector." ~ s);
	}

	void toString()(scope void delegate(const(char)[]) sink)
	{
		import std.format : formattedWrite;
		sink.formattedWrite("bcp(%(%s %))", vector.arrayof);
	}
}

struct ChunkRegionIndex
{
	this(ChunkRegionPos chunkRegionPos)
	{
		index = chunkRegionPos.x +
			chunkRegionPos.y * REGION_SIZE +
			chunkRegionPos.z * REGION_SIZE_SQR;
	}

	size_t index;

	size_t getIndex() @property { return index; }
	alias getIndex this;
}

// Position of chunk in world space. -int.max..int.max
struct ChunkWorldPos
{
	enum ChunkWorldPos MAX = ChunkWorldPos(svec4(short.max,short.max,short.max,short.max));

	this(BlockWorldPos blockWorldPos)
	{
		vector = svec4(
			floor(cast(float)blockWorldPos.x / CHUNK_SIZE),
			floor(cast(float)blockWorldPos.y / CHUNK_SIZE),
			floor(cast(float)blockWorldPos.z / CHUNK_SIZE),
			blockWorldPos.w);
	}

	this(ivec4 chunkWorldPos)
	{
		vector = chunkWorldPos;
	}

	this(int[4] chunkWorldPos)
	{
		vector = svec4(chunkWorldPos);
	}

	this(ivec3 chunkWorldPos, DimensionId dim)
	{
		vector = svec4(chunkWorldPos.x, chunkWorldPos.y, chunkWorldPos.z, dim);
	}

	this(svec4 chunkWorldPos)
	{
		vector = chunkWorldPos;
	}

	this(int x, int y, int z, int dim)
	{
		vector = svec4(x, y, z, dim);
	}

	this(ulong val)
	{
		enum MASK16 = 0b1111_1111_1111_1111;
		vector = svec4(val&MASK16, (val>>16)&MASK16, (val>>32)&MASK16, (val>>48)&MASK16);
	}

	svec4 vector;

	ivec4 ivector() @property
	{
		return ivec4(vector);
	}

	ivec3 ivector3() @property
	{
		return ivec3(vector);
	}

	ushort dimension() @property
	{
		return vector.w;
	}

	ulong asUlong() @property
	{
		ulong id = cast(ulong)vector.w<<48 |
				cast(ulong)(cast(ushort)vector.z)<<32 |
				cast(ulong)(cast(ushort)vector.y)<<16 |
				cast(ulong)(cast(ushort)vector.x);
		return id;
	}

	auto ref opDispatch(string s)()
	{
		return mixin("vector." ~ s);
	}

	void toString()(scope void delegate(const(char)[]) sink)
	{
		import std.format : formattedWrite;
		sink.formattedWrite("cwp(%(%s %))", vector.arrayof);
	}
}

void adjacentPositions(size_t numAdjacent, T)(T center, out T[numAdjacent] positions)
	if (numAdjacent == 6 || numAdjacent == 26)
{
	import voxelman.geometry : sideOffsets;
	foreach(i, offset; sideOffsets!numAdjacent)
	{
		positions[i] = T(center.x + offset[0],
			center.y + offset[1],
			center.z + offset[2],
			center.w);
	}
}

T[numAdjacent] adjacentPositions(size_t numAdjacent, T)(T center)
	if (numAdjacent == 6 || numAdjacent == 26)
{
	T[numAdjacent] positions;
	adjacentPositions(center, positions);
	return positions;
}

// Position of chunk in region space. 0..RegionSize
struct ChunkRegionPos
{
	this(ChunkWorldPos chunkWorldPos)
	{
		vector.x = chunkWorldPos.x % REGION_SIZE;
		vector.y = chunkWorldPos.y % REGION_SIZE;
		vector.z = chunkWorldPos.z % REGION_SIZE;
		if (vector.x < 0) vector.x += REGION_SIZE;
		if (vector.y < 0) vector.y += REGION_SIZE;
		if (vector.z < 0) vector.z += REGION_SIZE;
	}

	this(ivec3 blockWorldPos)
	{
		vector = blockWorldPos;
	}

	ivec3 vector;
	auto opDispatch(string s)()
	{
		return mixin("vector." ~ s);
	}
}

// Position of region in world space. -int.max..int.max
struct RegionWorldPos
{
	this(ChunkWorldPos chunkWorldPos)
	{
		vector = ivec3(
			floor(cast(float)chunkWorldPos.x / REGION_SIZE),
			floor(cast(float)chunkWorldPos.y / REGION_SIZE),
			floor(cast(float)chunkWorldPos.z / REGION_SIZE),);
	}

	this(ivec3 blockWorldPos)
	{
		vector = blockWorldPos;
	}

	ivec3 vector;
	auto opDispatch(string s)()
	{
		return mixin("vector." ~ s);
	}
}
