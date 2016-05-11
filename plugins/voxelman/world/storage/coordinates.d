/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.coordinates;

import voxelman.core.config;
import voxelman.world.storage.utils;
import voxelman.utils.math;
public import voxelman.core.config : DimentionId;

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

	ushort index;

	size_t getIndex() @property { return index; }
	alias getIndex this;
}

// Position of block in world space. -int.max..int.max
struct BlockWorldPos
{
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

	ivec4 vector;
	auto opDispatch(string s)()
	{
		return mixin("vector." ~ s);
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

	this(ivec3 blockChunkPos)
	{
		vector = blockChunkPos;
	}

	ivec3 vector;
	auto opDispatch(string s)()
	{
		return mixin("vector." ~ s);
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

alias Vector!(short, 4) svec4;

// Position of chunk in world space. -int.max..int.max
struct ChunkWorldPos
{
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

	this(ivec3 chunkWorldPos, DimentionId dim)
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
