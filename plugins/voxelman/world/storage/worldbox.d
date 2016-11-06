/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.worldbox;

import voxelman.log;
import voxelman.math;

import voxelman.core.config;
import voxelman.world.storage.coordinates;

import voxelman.graphics;
import voxelman.geometry.box;

void putCube(ref Batch batch, Box box, Color4ub color, bool fill, bool offset = true)
{
	vec3 pos = box.position;
	vec3 size = box.size;
	if (offset) {
		pos -= vec3(0.01, 0.01, 0.01);
		size += vec3(0.02, 0.02, 0.02);
	}
	batch.putCube(pos, size, color, fill);
}

WorldBox shiftAndClampBoxByBorders(WorldBox box, Box dimBorders)
{
	if (box.position.x < dimBorders.position.x)
		box.position.x = dimBorders.position.x;
	if (box.position.y < dimBorders.position.y)
		box.position.y = dimBorders.position.y;
	if (box.position.z < dimBorders.position.z)
		box.position.z = dimBorders.position.z;

	if (box.endPosition.x > dimBorders.endPosition.x)
		box.position.x = dimBorders.endPosition.x - box.size.x;
	if (box.endPosition.y > dimBorders.endPosition.y)
		box.position.y = dimBorders.endPosition.y - box.size.y;
	if (box.endPosition.z > dimBorders.endPosition.z)
		box.position.z = dimBorders.endPosition.z - box.size.z;

	return WorldBox(boxIntersection(box, dimBorders), box.dimension);
}

WorldBox calcBox(ChunkWorldPos cwp, int viewRadius)
{
	int size = viewRadius*2 + 1;
	return WorldBox(cast(ivec3)(cwp.ivector3 - viewRadius),
		ivec3(size, size, size), cwp.w);
}

WorldBox worldBoxFromCorners(ivec3 a, ivec3 b, ushort dimension)
{
	return WorldBox(boxFromCorners(a, b), dimension);
}

WorldBox blockBoxToChunkBox(WorldBox blockBox)
{
	auto startPosition = blockToChunkPosition(blockBox.position);
	auto endPosition = blockToChunkPosition(blockBox.endPosition);
	return worldBoxFromCorners(startPosition, endPosition, blockBox.dimension);
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
	return chunkToBlockBox(cwp.ivector3, cwp.dimension);
}

WorldBox chunkToBlockBox(ivec3 cwp, ushort dimension) {
	ivec3 startPosition = chunkToBlockPosition(cwp);
	return WorldBox(startPosition, CHUNK_SIZE_VECTOR, dimension);
}

Box chunkToBlockBox(ivec3 cwp) {
	ivec3 startPosition = chunkToBlockPosition(cwp);
	return Box(startPosition, CHUNK_SIZE_VECTOR);
}

struct WorldBox
{
	Box box;
	alias box this;
	ushort dimension;

	this(ivec3 pos, ivec3 size, ushort dim)
	{
		box = Box(pos, size);
		dimension = dim;
	}

	this(Box box, ushort dim)
	{
		this.box = box;
		dimension = dim;
	}

	bool contains(ivec3 point, ushort dimension) const
	{
		if (this.dimension != dimension) return false;
		return box.contains(point);
	}

	import std.algorithm : cartesianProduct, map, joiner, equal, canFind;
	import std.range : iota, walkLength;
	import std.array : array;

	/// iterate all posisions within a box
	int opApply(scope int delegate(ivec4) del) {
		foreach (y; position.y .. position.y + size.y)
		foreach (z; position.z .. position.z + size.z)
		foreach (x; position.x .. position.x + size.x)
			if (auto ret = del(ivec4(x, y, z, dimension)))
				return ret;
		return 0;
	}

	/// ditto
	int opApply(scope int delegate(ChunkWorldPos) del) {
		foreach (y; position.y .. position.y + size.y)
		foreach (z; position.z .. position.z + size.z)
		foreach (x; position.x .. position.x + size.x)
			if (auto ret = del(ChunkWorldPos(x, y, z, dimension)))
				return ret;
		return 0;
	}

	WorldBox intersection(WorldBox other) {
		return worldBoxIntersection(this, other);
	}

	WorldBox intersection(Box other) {
		return WorldBox(boxIntersection(this, other), dimension);
	}

	bool opEquals()(auto const ref WorldBox other) const
	{
		return box == other.box && dimension == other.dimension;
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
	if (a.dimension != b.dimension)
	{
		return WorldBox();
	}

	auto box = boxIntersection(a.box, b.box);
	return WorldBox(box, a.dimension);
}
