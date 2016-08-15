/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.worldbox;

import std.experimental.logger;
import voxelman.math;

import voxelman.core.config;
import voxelman.world.storage.coordinates;

import voxelman.utils.renderutils;
import voxelman.geometry.box;

void putCube(ref Batch batch, Box box, Color3ub color, bool fill, bool offset = true)
{
	vec3 pos = box.position;
	vec3 size = box.size;
	if (offset) {
		pos -= vec3(0.01, 0.01, 0.01);
		size += vec3(0.02, 0.02, 0.02);
	}
	batch.putCube(pos, size, color, fill);
}

WorldBox calcBox(ChunkWorldPos cwp, int viewRadius)
{
	int size = viewRadius*2 + 1;
	return WorldBox(cast(ivec3)(cwp.ivector3 - viewRadius),
		ivec3(size, size, size), cwp.w);
}

WorldBox worldBoxFromCorners(ivec3 a, ivec3 b, ushort dimention)
{
	return WorldBox(boxFromCorners(a, b), dimention);
}

WorldBox blockBoxToChunkBox(WorldBox blockBox)
{
	auto startPosition = blockToChunkPosition(blockBox.position);
	auto endPosition = blockToChunkPosition(blockBox.endPosition);
	return worldBoxFromCorners(startPosition, endPosition, blockBox.dimention);
}

// makes block box in chunk-local space out of world space
WorldBox blockBoxToChunkLocalBox(WorldBox blockBox)
{
	blockBox.position -= chunkStartBlockPos(blockBox.position);
	return blockBox;
}

/// Returns chunks if their mesh may have changed after specified modification
/// WorldBox is specified in block space
WorldBox calcModifiedMeshesBox(WorldBox modificationBox)
{
	// We increase size by 1 in every direction.
	// After rounding chunks on the border of modification will be included
	WorldBox expandedBox = modificationBox;
	expandedBox.position -= ivec3(1,1,1);
	expandedBox.size += ivec3(2,2,2);
	WorldBox chunkBox = blockBoxToChunkBox(expandedBox);
	return chunkBox;
}

WorldBox chunkToBlockBox(ChunkWorldPos cwp) {
	return chunkToBlockBox(cwp.ivector3, cwp.dimention);
}

WorldBox chunkToBlockBox(ivec3 cwp, ushort dimention) {
	ivec3 startPosition = chunkToBlockPosition(cwp);
	return WorldBox(startPosition, CHUNK_SIZE_VECTOR, dimention);
}

Box chunkToBlockBox(ivec3 cwp) {
	ivec3 startPosition = chunkToBlockPosition(cwp);
	return Box(startPosition, CHUNK_SIZE_VECTOR);
}

struct WorldBox
{
	Box box;
	alias box this;
	ushort dimention;

	this(ivec3 pos, ivec3 size, ushort dim)
	{
		box = Box(pos, size);
		dimention = dim;
	}

	this(Box box, ushort dim)
	{
		this.box = box;
		dimention = dim;
	}

	bool contains(ivec3 point, ushort dimention) const
	{
		if (this.dimention != dimention) return false;
		return box.contains(point);
	}

	import std.algorithm : cartesianProduct, map, joiner, equal, canFind;
	import std.range : iota, walkLength;
	import std.array : array;

	// generates all positions within box.
	auto positions4d() const @property
	{
		return cartesianProduct(
			iota(position.x, position.x + size.x),
			iota(position.y, position.y + size.y),
			iota(position.z, position.z + size.z))
			.map!((a)=>ivec4(a[0], a[1], a[2], dimention));
	}

	bool opEquals()(auto const ref WorldBox other) const
	{
		return box == other.box && dimention == other.dimention;
	}
}

TrisectResult trisect4d(WorldBox a, WorldBox b)
{
	WorldBox intersection = worldBoxIntersection(a, b);

	// no intersection
	if (intersection.empty)
	{
		return TrisectResult([a], Box(), [b]);
	}

	auto result = trisectIntersecting(a, b);
	result.intersection = intersection;
	return result;
}

unittest
{
	assert(WorldBox(Box(), 0) != WorldBox(Box(), 1));
	assert(WorldBox(Box(), 0) == WorldBox(Box(), 0));
}

WorldBox worldBoxIntersection(WorldBox a, WorldBox b)
{
	if (a.dimention != b.dimention)
	{
		return WorldBox();
	}

	auto box = boxIntersection(a.box, b.box);
	return WorldBox(box, a.dimention);
}
