/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.storage.utils;

import std.experimental.logger;
import std.math : floor;
import std.range : chain, only;
import dlib.math.vector;

import voxelman.config;
import voxelman.storage.region;

size_t manhattanDist(ivec3 coord, ivec3 other)
{
	return other.x > coord.x ? other.x - coord.x : coord.x - other.x +
			other.y > coord.y ? other.y - coord.y : coord.y - other.y +
			other.z > coord.z ? other.z - coord.z : coord.z - other.z;
}

double euclidDist(ivec3 coord, ivec3 other)
{
	import std.math : sqrt;
	return sqrt(cast(real)(coord.x - other.x)^^2 +
			(coord.y - other.y)^^2 +
			(coord.z - other.z)^^2);
}

size_t euclidDistSqr(ivec3 coord, ivec3 other)
{
	return (coord.x - other.x)^^2 + (coord.y - other.y)^^2 + (coord.z - other.z)^^2;
}

ivec3 calcRegionPos(ivec3 chunkWorldPos)
{
	return ivec3(
		floor(chunkWorldPos.x / cast(float)REGION_SIZE),
		floor(chunkWorldPos.y / cast(float)REGION_SIZE),
		floor(chunkWorldPos.z / cast(float)REGION_SIZE));
}

// chunk position within region
ivec3 calcRegionLocalPos(ivec3 chunkWorldPos)
{
	chunkWorldPos.x %= REGION_SIZE;
	chunkWorldPos.y %= REGION_SIZE;
	chunkWorldPos.z %= REGION_SIZE;
	if (chunkWorldPos.x < 0) chunkWorldPos.x += REGION_SIZE;
	if (chunkWorldPos.y < 0) chunkWorldPos.y += REGION_SIZE;
	if (chunkWorldPos.z < 0) chunkWorldPos.z += REGION_SIZE;
	return chunkWorldPos;
}

ChunkRange calcChunkRange(ivec3 coord, int viewRadius)
{
	int size = viewRadius*2 + 1;
	return ChunkRange(cast(ivec3)(coord - viewRadius),
		ivec3(size, size, size));
}

ivec3 worldToChunkPos(vec3 worldPos)
{
	import voxelman.utils.math : nansToZero;

	nansToZero(worldPos);
	return ivec3(
		floor(worldPos.x / CHUNK_SIZE),
		floor(worldPos.y / CHUNK_SIZE),
		floor(worldPos.z / CHUNK_SIZE),);
}

ivec3 worldToChunkPos(ivec3 worldPos)
{
	return ivec3(
		floor(cast(float)worldPos.x / CHUNK_SIZE),
		floor(cast(float)worldPos.y / CHUNK_SIZE),
		floor(cast(float)worldPos.z / CHUNK_SIZE),);
}

// converts global position to position in the chunk
vec3 worldToChunkLocalPos(vec3 worldPos)
{
	import voxelman.utils.math : nansToZero;

	nansToZero(worldPos);
	worldPos.x %= CHUNK_SIZE;
	worldPos.y %= CHUNK_SIZE;
	worldPos.z %= CHUNK_SIZE;
	if (worldPos.x < 0) worldPos.x += CHUNK_SIZE;
	if (worldPos.y < 0) worldPos.y += CHUNK_SIZE;
	if (worldPos.z < 0) worldPos.z += CHUNK_SIZE;
	return worldPos;
}

ivec3 worldToChunkLocalPos(ivec3 worldPos)
{
	worldPos.x %= CHUNK_SIZE;
	worldPos.y %= CHUNK_SIZE;
	worldPos.z %= CHUNK_SIZE;
	if (worldPos.x < 0) worldPos.x += CHUNK_SIZE;
	if (worldPos.y < 0) worldPos.y += CHUNK_SIZE;
	if (worldPos.z < 0) worldPos.z += CHUNK_SIZE;
	return worldPos;
}


ushort worldToChunkBlockIndex(vec3 worldPos)
{
	ivec3 localPos = ivec3(worldToChunkLocalPos(worldPos));
	return cast(ushort)blockIndex(cast(ubyte)localPos.x, cast(ubyte)localPos.y, cast(ubyte)localPos.z);
}

ushort worldToChunkBlockIndex(ivec3 worldPos)
{
	ivec3 localPos = ivec3(worldToChunkLocalPos(worldPos));
	return cast(ushort)blockIndex(cast(ubyte)localPos.x, cast(ubyte)localPos.y, cast(ubyte)localPos.z);
}

// 3d slice of chunks
struct ChunkRange
{
	ivec3 coord;
	ivec3 size;

	int volume()
	{
		return size.x * size.y * size.z;
	}

	bool empty() @property
	{
		return size.x == 0 && size.y == 0 && size.z == 0;
	}

	bool contains(ivec3 otherCoord)
	{
		if (otherCoord.x < coord.x || otherCoord.x >= coord.x + size.x) return false;
		if (otherCoord.y < coord.y || otherCoord.y >= coord.y + size.y) return false;
		if (otherCoord.z < coord.z || otherCoord.z >= coord.z + size.z) return false;
		return true;
	}

	bool opEquals()(auto ref const ChunkRange other) const
	{
		return coord == other.coord && size == other.size;
	}

	import std.algorithm : cartesianProduct, map, joiner, equal, canFind;
	import std.range : iota, walkLength;
	import std.array : array;

	// generates all chunk coordinates that are contained inside chunk range.
	auto chunkCoords() @property
	{
		return cartesianProduct(
			iota(coord.x, coord.x + size.x),
			iota(coord.y, coord.y + size.y),
			iota(coord.z, coord.z + size.z))
			.map!((a)=>ivec3(a[0], a[1], a[2]));
	}

	unittest
	{
		assert(ChunkRange(ivec3(0,0,0), ivec3(3,3,3)).chunkCoords.walkLength == 27);
	}

	auto chunksNotIn(ChunkRange other)
	{
		import std.algorithm : filter;

		auto intersection = rangeIntersection(this, other);
		ChunkRange[] ranges;

		if (intersection.size == ivec3(0,0,0))
			ranges = [this];
		else
			ranges = octoSlice(intersection)[]
				.filter!((a) => a != intersection)
				.array;

		return ranges
			.map!((a) => a.chunkCoords)
			.joiner;
	}

	unittest
	{
		ChunkRange cr = {{0,0,0}, {2,2,2}};
		ChunkRange other1 = {{1,1,1}, {2,2,2}}; // opposite intersection {1,1,1}
		ChunkRange other2 = {{2,2,2}, {2,2,2}}; // no intersection
		ChunkRange other3 = {{0,0,1}, {2,2,2}}; // half intersection
		ChunkRange other4 = {{0,0,-1}, {2,2,2}}; // half intersection

		ChunkRange half1 = {{0,0,0}, {2,2,1}};
		ChunkRange half2 = {{0,0,1}, {2,2,1}};

		assert( !cr.chunksNotIn(other1).canFind(ivec3(1,1,1)) );
		assert( equal(cr.chunksNotIn(other2), cr.chunkCoords) );
		assert( equal(cr.chunksNotIn(other3), half1.chunkCoords) );
		assert( equal(cr.chunksNotIn(other4), half2.chunkCoords) );
	}

	/// Slice range in 8 pieces as octree by corner piece.
	/// Return all 8 pieces.
	/// corner piece must be in the corner of this range.
	ChunkRange[8] octoSlice(ChunkRange corner)
	{
		// opposite corner coordinates.
		int cx, cy, cz;

		if (corner.coord.x == coord.x) // x0
			cx = (corner.coord.x + corner.size.x);
		else // x1
			cx = corner.coord.x;

		if (corner.coord.y == coord.y) // y0
			cy = (corner.coord.y + corner.size.y);
		else // y1
			cy = corner.coord.y;

		if (corner.coord.z == coord.z) // z0
			cz = (corner.coord.z + corner.size.z);
		else // z1
			cz = corner.coord.z;


		// origin coordinates
		int ox = coord.x, oy = coord.y, oz = coord.z;
		// opposite corner size.
		int csizex = size.x-(cx-ox), csizey = size.y-(cy-oy), csizez = size.z-(cz-oz);
		// origin size
		int osizex = size.x-csizex, osizey = size.y-csizey, osizez = size.z-csizez;
		//tracef("cx %s cy %s cz %s", cx, cy, cz);
		//tracef("csizex %s csizey %s csizez %s", csizex, csizey, csizez);
		//tracef("ox %s oy %s oz %s", ox, oy, oz);
		//tracef("osizex %s osizey %s osizez %s", osizex, osizey, osizez);
		//tracef("sizex %s sizey %s sizez %s", size.x, size.y, size.z);
		//tracef("Corner %s", corner);

		ChunkRange rx0y0z0 = {ivec3(ox,oy,oz), ivec3(osizex, osizey, osizez)};
		ChunkRange rx0y0z1 = {ivec3(ox,oy,cz), ivec3(osizex, osizey, csizez)};
		ChunkRange rx0y1z0 = {ivec3(ox,cy,oz), ivec3(osizex, csizey, osizez)};
		ChunkRange rx0y1z1 = {ivec3(ox,cy,cz), ivec3(osizex, csizey, csizez)};

		ChunkRange rx1y0z0 = {ivec3(cx,oy,oz), ivec3(csizex, osizey, osizez)};
		ChunkRange rx1y0z1 = {ivec3(cx,oy,cz), ivec3(csizex, osizey, csizez)};
		ChunkRange rx1y1z0 = {ivec3(cx,cy,oz), ivec3(csizex, csizey, osizez)};
		ChunkRange rx1y1z1 = {ivec3(cx,cy,cz), ivec3(csizex, csizey, csizez)};

		return [
		rx0y0z0, rx0y0z1, rx0y1z0, rx0y1z1,
		rx1y0z0, rx1y0z1, rx1y1z0, rx1y1z1];
	}
}

struct TrisectResult
{
	ChunkRange[] aChunkRanges;
	ChunkRange intersection;
	ChunkRange[] bChunkRanges;
	import std.algorithm : map, joiner;
	auto aChunkCoords() @property
	{
		return aChunkRanges.map!(a => a.chunkCoords).joiner;
	}
	auto bChunkCoords() @property
	{
		return bChunkRanges.map!(a => a.chunkCoords).joiner;
	}
}

// Finds intersection between two boxes
// [0] a - b  == a if no intersection
// [1] a intersects b
// [2] b - a  == b if no intersection
TrisectResult trisect(ChunkRange a, ChunkRange b)
{
	// no intersection
	if (rangeIntersection(a, b).empty)
	{
		return TrisectResult([a], ChunkRange(), [b]);
	}

	auto xTrisect = trisectAxis(a.coord.x, a.coord.x + a.size.x, b.coord.x, b.coord.x + b.size.x);
	auto yTrisect = trisectAxis(a.coord.y, a.coord.y + a.size.y, b.coord.y, b.coord.y + b.size.y);
	auto zTrisect = trisectAxis(a.coord.z, a.coord.z + a.size.z, b.coord.z, b.coord.z + b.size.z);

	TrisectResult result;

	foreach(xa; xTrisect.aranges[0..xTrisect.numRangesA].chain(only(xTrisect.irange)))
	foreach(ya; yTrisect.aranges[0..yTrisect.numRangesA].chain(only(yTrisect.irange)))
	foreach(za; zTrisect.aranges[0..zTrisect.numRangesA].chain(only(zTrisect.irange)))
	{
		if (!(xa.isIntersection && ya.isIntersection && za.isIntersection))
			result.aChunkRanges ~= ChunkRange(ivec3(xa.start, ya.start, za.start),
				ivec3(xa.length, ya.length, za.length));
	}

	foreach(xb; xTrisect.branges[0..xTrisect.numRangesB].chain(only(xTrisect.irange)))
	foreach(yb; yTrisect.branges[0..yTrisect.numRangesB].chain(only(yTrisect.irange)))
	foreach(zb; zTrisect.branges[0..zTrisect.numRangesB].chain(only(zTrisect.irange)))
	{
		if (!(xb.isIntersection && yb.isIntersection && zb.isIntersection))
			result.bChunkRanges ~= ChunkRange(ivec3(xb.start, yb.start, zb.start),
				ivec3(xb.length, yb.length, zb.length));
	}

	result.intersection = ChunkRange(
		ivec3(xTrisect.irange.start, yTrisect.irange.start, zTrisect.irange.start),
		ivec3(xTrisect.irange.length, yTrisect.irange.length, zTrisect.irange.length));

	return result;
}

struct AxisRange
{
	int start;
	int end;
	bool isIntersection;
	int length() @property
	out (result)
	{
		assert(result >= 0);
	}
	body
	{
		return end - start;
	}
}

struct TrisectAxisResult
{
	AxisRange[2] aranges;
	ubyte numRangesA;
	AxisRange irange;
	AxisRange[2] branges;
	ubyte numRangesB;
}

// a  aStart *----* aEnd
// b    bStart *----* bEnd
// does not handle situation when there is no intersection
TrisectAxisResult trisectAxis(int aStart, int aEnd, int bStart, int bEnd)
{
	TrisectAxisResult res;

	if (aStart < bStart)
	{
		res.aranges[res.numRangesA++] = AxisRange(aStart, bStart);
		// bOnlyStart1 = 0
		// bOnlyEnd1 = 0
		res.irange.start = bStart;
	}
	else if (aStart > bStart)
	{
		// aOnlyStart1 = 0
		// aOnlyEnd1 = 0
		res.branges[res.numRangesB++] = AxisRange(bStart, aStart);
		res.irange.start = aStart;
	}
	else
	{
		// aOnlyStart1 = 0
		// aOnlyEnd1 = 0
		// bOnlyStart1 = 0
		// bOnlyEnd1 = 0
		res.irange.start = aStart;
	}

	if (aEnd < bEnd)
	{
		res.irange.end = aEnd;
		// aOnlyStart2 = 0
		// aOnlyEnd2 = 0
		res.branges[res.numRangesB++] = AxisRange(aEnd, bEnd);
	}
	else if (aEnd > bEnd)
	{
		res.irange.end = bEnd;
		res.aranges[res.numRangesA++] = AxisRange(bEnd, aEnd);
		// bOnlyStart2 = 0
		// bOnlyEnd2 = 0
	}
	else
	{
		res.irange.end = bEnd;
		// aOnlyStart2 = 0
		// aOnlyEnd2 = 0
		// bOnlyStart2 = 0
		// bOnlyEnd2 = 0
	}

	res.irange.isIntersection = true;

	return res;
}

ChunkRange rangeIntersection(ChunkRange r1, ChunkRange r2)
{
	ChunkRange result;
	if (r1.coord.x < r2.coord.x)
	{
		if (r1.coord.x + r1.size.x < r2.coord.x) return ChunkRange();
		result.coord.x = r2.coord.x;
		result.size.x = r1.size.x - (r2.coord.x - r1.coord.x);
	}
	else
	{
		if (r2.coord.x + r2.size.x < r1.coord.x) return ChunkRange();
		result.coord.x = r1.coord.x;
		result.size.x = r2.size.x - (r1.coord.x - r2.coord.x);
	}

	if (r1.coord.y < r2.coord.y)
	{
		if (r1.coord.y + r1.size.y < r2.coord.y) return ChunkRange();
		result.coord.y = r2.coord.y;
		result.size.y = r1.size.y - (r2.coord.y - r1.coord.y);
	}
	else
	{
		if (r2.coord.y + r2.size.y < r1.coord.y) return ChunkRange();
		result.coord.y = r1.coord.y;
		result.size.y = r2.size.y - (r1.coord.y - r2.coord.y);
	}

	if (r1.coord.z < r2.coord.z)
	{
		if (r1.coord.z + r1.size.z < r2.coord.z) return ChunkRange();
		result.coord.z = r2.coord.z;
		result.size.z = r1.size.z - (r2.coord.z - r1.coord.z);
	}
	else
	{
		if (r2.coord.z + r2.size.z < r1.coord.z) return ChunkRange();
		result.coord.z = r1.coord.z;
		result.size.z = r2.size.z - (r1.coord.z - r2.coord.z);
	}

	result.size.x = result.size.x > 0 ? result.size.x : -result.size.x;
	result.size.y = result.size.y > 0 ? result.size.y : -result.size.y;
	result.size.z = result.size.z > 0 ? result.size.z : -result.size.z;

	return result;
}

unittest
{
	assert(rangeIntersection(
		ChunkRange(ivec3(0,0,0), ivec3(2,2,2)),
		ChunkRange(ivec3(1,1,1), ivec3(2,2,2))) ==
		ChunkRange(ivec3(1,1,1), ivec3(1,1,1)));
	assert(rangeIntersection(
		ChunkRange(ivec3(0,0,0), ivec3(2,2,2)),
		ChunkRange(ivec3(3,3,3), ivec3(4,4,4))) ==
		ChunkRange(ivec3()));
	assert(rangeIntersection(
		ChunkRange(ivec3(1,1,1), ivec3(2,2,2)),
		ChunkRange(ivec3(0,0,0), ivec3(2,2,2))) ==
		ChunkRange(ivec3(1,1,1), ivec3(1,1,1)));
	assert(rangeIntersection(
		ChunkRange(ivec3(1,1,1), ivec3(1,1,1)),
		ChunkRange(ivec3(1,1,1), ivec3(1,1,1))) ==
		ChunkRange(ivec3(1,1,1), ivec3(1,1,1)));
	assert(rangeIntersection(
		ChunkRange(ivec3(0,0,0), ivec3(2,2,2)),
		ChunkRange(ivec3(0,0,-1), ivec3(2,2,2))) ==
		ChunkRange(ivec3(0,0,0), ivec3(2,2,1)));
}

// returns index of block in blockData from local block position
size_t blockIndex(ubyte x, ubyte y, ubyte z)
{
	return x + y * CHUNK_SIZE_SQR + z * CHUNK_SIZE;
}
