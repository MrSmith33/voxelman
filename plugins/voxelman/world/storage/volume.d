/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.volume;

import std.experimental.logger;
import std.algorithm : alg_min = min, alg_max = max;
import std.math : floor;
import std.range : chain, only;
import dlib.math.vector;

import voxelman.world.storage.coordinates;

Volume calcVolume(ChunkWorldPos cwp, int viewRadius, ushort dimention = 0)
{
	int size = viewRadius*2 + 1;
	return Volume(cast(ivec3)(cwp.ivector - viewRadius),
		ivec3(size, size, size), dimention);
}

Volume volumeFromCorners(ivec3 a, ivec3 b, ushort dimention = 0)
{
	Volume vol;
	vol.position = min(a, b);
	vol.dimention = dimention;
	vol.size = max(a, b) - vol.position + ivec3(1,1,1);
	return vol;
}

Vector!(T, size) min(T, int size)(Vector!(T, size) a, Vector!(T, size) b)
{
	Vector!(T, size) res;
	foreach(i; 0..size)
		res.arrayof[i] = alg_min(a.arrayof[i], b.arrayof[i]);
	return res;
}

Vector!(T, size) max(T, int size)(Vector!(T, size) a, Vector!(T, size) b)
{
	Vector!(T, size) res;
	foreach(i; 0..size)
		res.arrayof[i] = alg_max(a.arrayof[i], b.arrayof[i]);
	return res;
}

// 3d grid volume
struct Volume
{
	ivec3 position;
	ivec3 size;
	ushort dimention;

	int volume()
	{
		return size.x * size.y * size.z;
	}

	bool empty() @property
	{
		return size.x == 0 && size.y == 0 && size.z == 0;
	}

	bool contains(ivec3 point)
	{
		if (point.x < position.x || point.x >= position.x + size.x) return false;
		if (point.y < position.y || point.y >= position.y + size.y) return false;
		if (point.z < position.z || point.z >= position.z + size.z) return false;
		return true;
	}

	bool contains(ivec3 point, ushort dimention)
	{
		if (this.dimention != dimention) return false;
		if (point.x < position.x || point.x >= position.x + size.x) return false;
		if (point.y < position.y || point.y >= position.y + size.y) return false;
		if (point.z < position.z || point.z >= position.z + size.z) return false;
		return true;
	}

	bool opEquals()(auto ref const Volume other) const
	{
		return position == other.position && size == other.size && dimention == other.dimention;
	}

	import std.algorithm : cartesianProduct, map, joiner, equal, canFind;
	import std.range : iota, walkLength;
	import std.array : array;

	// generates all positions within volume.
	auto positions() @property
	{
		return cartesianProduct(
			iota(position.x, position.x + size.x),
			iota(position.y, position.y + size.y),
			iota(position.z, position.z + size.z))
			.map!((a)=>ivec3(a[0], a[1], a[2]));
	}

	unittest
	{
		assert(Volume(ivec3(0,0,0), ivec3(3,3,3)).positions.walkLength == 27);
	}
}

struct TrisectResult
{
	Volume[] aVolumes;
	Volume intersection;
	Volume[] bVolumes;
	import std.algorithm : map, joiner;
	auto aPositions() @property
	{
		return aVolumes.map!(a => a.positions).joiner;
	}
	auto bPositions() @property
	{
		return bVolumes.map!(a => a.positions).joiner;
	}
}

// Finds intersection between two boxes
// [0] a - b  == a if no intersection
// [1] a intersects b
// [2] b - a  == b if no intersection
TrisectResult trisect(Volume a, Volume b)
{
	// no intersection
	if (rangeIntersection(a, b).empty)
	{
		return TrisectResult([a], Volume(), [b]);
	}

	auto xTrisect = trisectAxis(a.position.x, a.position.x + a.size.x, b.position.x, b.position.x + b.size.x);
	auto yTrisect = trisectAxis(a.position.y, a.position.y + a.size.y, b.position.y, b.position.y + b.size.y);
	auto zTrisect = trisectAxis(a.position.z, a.position.z + a.size.z, b.position.z, b.position.z + b.size.z);

	TrisectResult result;

	foreach(xa; xTrisect.aranges[0..xTrisect.numRangesA].chain(only(xTrisect.irange)))
	foreach(ya; yTrisect.aranges[0..yTrisect.numRangesA].chain(only(yTrisect.irange)))
	foreach(za; zTrisect.aranges[0..zTrisect.numRangesA].chain(only(zTrisect.irange)))
	{
		if (!(xa.isIntersection && ya.isIntersection && za.isIntersection))
			result.aVolumes ~= Volume(ivec3(xa.start, ya.start, za.start),
				ivec3(xa.length, ya.length, za.length));
	}

	foreach(xb; xTrisect.branges[0..xTrisect.numRangesB].chain(only(xTrisect.irange)))
	foreach(yb; yTrisect.branges[0..yTrisect.numRangesB].chain(only(yTrisect.irange)))
	foreach(zb; zTrisect.branges[0..zTrisect.numRangesB].chain(only(zTrisect.irange)))
	{
		if (!(xb.isIntersection && yb.isIntersection && zb.isIntersection))
			result.bVolumes ~= Volume(ivec3(xb.start, yb.start, zb.start),
				ivec3(xb.length, yb.length, zb.length));
	}

	result.intersection = Volume(
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

Volume rangeIntersection(Volume a, Volume b)
{
	Volume result;
	if (a.position.x < b.position.x)
	{
		if (a.position.x + a.size.x < b.position.x) return Volume();
		result.position.x = b.position.x;
		result.size.x = a.size.x - (b.position.x - a.position.x);
	}
	else
	{
		if (b.position.x + b.size.x < a.position.x) return Volume();
		result.position.x = a.position.x;
		result.size.x = b.size.x - (a.position.x - b.position.x);
	}

	if (a.position.y < b.position.y)
	{
		if (a.position.y + a.size.y < b.position.y) return Volume();
		result.position.y = b.position.y;
		result.size.y = a.size.y - (b.position.y - a.position.y);
	}
	else
	{
		if (b.position.y + b.size.y < a.position.y) return Volume();
		result.position.y = a.position.y;
		result.size.y = b.size.y - (a.position.y - b.position.y);
	}

	if (a.position.z < b.position.z)
	{
		if (a.position.z + a.size.z < b.position.z) return Volume();
		result.position.z = b.position.z;
		result.size.z = a.size.z - (b.position.z - a.position.z);
	}
	else
	{
		if (b.position.z + b.size.z < a.position.z) return Volume();
		result.position.z = a.position.z;
		result.size.z = b.size.z - (a.position.z - b.position.z);
	}

	result.size.x = result.size.x > 0 ? result.size.x : -result.size.x;
	result.size.y = result.size.y > 0 ? result.size.y : -result.size.y;
	result.size.z = result.size.z > 0 ? result.size.z : -result.size.z;

	return result;
}

unittest
{
	assert(rangeIntersection(
		Volume(ivec3(0,0,0), ivec3(2,2,2)),
		Volume(ivec3(1,1,1), ivec3(2,2,2))) ==
		Volume(ivec3(1,1,1), ivec3(1,1,1)));
	assert(rangeIntersection(
		Volume(ivec3(0,0,0), ivec3(2,2,2)),
		Volume(ivec3(3,3,3), ivec3(4,4,4))) ==
		Volume(ivec3()));
	assert(rangeIntersection(
		Volume(ivec3(1,1,1), ivec3(2,2,2)),
		Volume(ivec3(0,0,0), ivec3(2,2,2))) ==
		Volume(ivec3(1,1,1), ivec3(1,1,1)));
	assert(rangeIntersection(
		Volume(ivec3(1,1,1), ivec3(1,1,1)),
		Volume(ivec3(1,1,1), ivec3(1,1,1))) ==
		Volume(ivec3(1,1,1), ivec3(1,1,1)));
	assert(rangeIntersection(
		Volume(ivec3(0,0,0), ivec3(2,2,2)),
		Volume(ivec3(0,0,-1), ivec3(2,2,2))) ==
		Volume(ivec3(0,0,0), ivec3(2,2,1)));
}
