/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.geometry.box;

import std.algorithm : alg_min = min, alg_max = max;
import std.range : chain, only;
import voxelman.math;

Box boxFromCorners(ivec3 a, ivec3 b)
{
	Box box;
	box.position = min(a, b);
	box.size = max(a, b) - box.position + ivec3(1,1,1);
	return box;
}

struct Box
{
	ivec3 position;
	ivec3 size;

	int box() @property const
	{
		return size.x * size.y * size.z;
	}

	ivec3 endPosition() @property const
	{
		return position + size - ivec3(1,1,1);
	}

	bool empty() const @property
	{
		return size.x == 0 && size.y == 0 && size.z == 0;
	}

	bool contains(ivec3 point) const
	{
		if (point.x < position.x || point.x >= position.x + size.x) return false;
		if (point.y < position.y || point.y >= position.y + size.y) return false;
		if (point.z < position.z || point.z >= position.z + size.z) return false;
		return true;
	}

	import std.algorithm : cartesianProduct, map, joiner, equal, canFind;
	import std.range : iota, walkLength;
	import std.array : array;

	// generates all positions within box.
	auto positions() const @property
	{
		return cartesianProduct(
			iota(position.x, position.x + size.x),
			iota(position.y, position.y + size.y),
			iota(position.z, position.z + size.z))
			.map!((a)=>ivec3(a[0], a[1], a[2]));
	}

	unittest
	{
		assert(Box(ivec3(0,0,0), ivec3(3,3,3)).positions.walkLength == 27);
	}
}

struct TrisectResult
{
	Box[] aBoxes;
	Box intersection;
	Box[] bBoxes;
	import std.algorithm : map, joiner;
	auto aPositions() @property
	{
		return aBoxes.map!(a => a.positions).joiner;
	}
	auto bPositions() @property
	{
		return bBoxes.map!(a => a.positions).joiner;
	}
}

// Finds intersection between two boxes
// TrisectResult[0] a - b  == a if no intersection
// TrisectResult[1] a intersects b
// TrisectResult[2] b - a  == b if no intersection
TrisectResult trisect(Box a, Box b)
{
	Box intersection = boxIntersection(a, b);

	// no intersection
	if (intersection.empty)
	{
		return TrisectResult([a], Box(), [b]);
	}

	auto result = trisectIntersecting(a, b);
	result.intersection = intersection;
	return result;
}

/// Assumes that boxes have intersection. Does not write to intersection
TrisectResult trisectIntersecting(Box a, Box b)
{
	TrisectResult result;

	auto xTrisect = trisectAxis(a.position.x, a.position.x + a.size.x, b.position.x, b.position.x + b.size.x);
	auto yTrisect = trisectAxis(a.position.y, a.position.y + a.size.y, b.position.y, b.position.y + b.size.y);
	auto zTrisect = trisectAxis(a.position.z, a.position.z + a.size.z, b.position.z, b.position.z + b.size.z);

	foreach(xa; xTrisect.aranges[0..xTrisect.numRangesA].chain(only(xTrisect.irange)))
	foreach(ya; yTrisect.aranges[0..yTrisect.numRangesA].chain(only(yTrisect.irange)))
	foreach(za; zTrisect.aranges[0..zTrisect.numRangesA].chain(only(zTrisect.irange)))
	{
		if (!(xa.isIntersection && ya.isIntersection && za.isIntersection))
			result.aBoxes ~= Box(ivec3(xa.start, ya.start, za.start),
				ivec3(xa.length, ya.length, za.length));
	}

	foreach(xb; xTrisect.branges[0..xTrisect.numRangesB].chain(only(xTrisect.irange)))
	foreach(yb; yTrisect.branges[0..yTrisect.numRangesB].chain(only(yTrisect.irange)))
	foreach(zb; zTrisect.branges[0..zTrisect.numRangesB].chain(only(zTrisect.irange)))
	{
		if (!(xb.isIntersection && yb.isIntersection && zb.isIntersection))
			result.bBoxes ~= Box(ivec3(xb.start, yb.start, zb.start),
				ivec3(xb.length, yb.length, zb.length));
	}

	return result;
}

struct AxisRange
{
	int start;
	int end;
	bool isIntersection;
	int length() @property
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

Box boxIntersection(Box a, Box b)
{
	auto xTrisect = trisectAxis(a.position.x, a.position.x + a.size.x, b.position.x, b.position.x + b.size.x);
	auto yTrisect = trisectAxis(a.position.y, a.position.y + a.size.y, b.position.y, b.position.y + b.size.y);
	auto zTrisect = trisectAxis(a.position.z, a.position.z + a.size.z, b.position.z, b.position.z + b.size.z);

	Box result = Box(
			ivec3(xTrisect.irange.start, yTrisect.irange.start, zTrisect.irange.start),
			ivec3(xTrisect.irange.length, yTrisect.irange.length, zTrisect.irange.length));

	foreach(elem; result.size.arrayof) {
		if (elem <= 0)
			return Box();
	}

	return result;
}

unittest
{
	assert(boxIntersection(
		Box(ivec3(0,0,0), ivec3(2,2,2)),
		Box(ivec3(1,1,1), ivec3(2,2,2))) ==
		Box(ivec3(1,1,1), ivec3(1,1,1)));
	assert(boxIntersection(
		Box(ivec3(0,0,0), ivec3(2,2,2)),
		Box(ivec3(3,3,3), ivec3(4,4,4))) ==
		Box(ivec3()));
	assert(boxIntersection(
		Box(ivec3(1,1,1), ivec3(2,2,2)),
		Box(ivec3(0,0,0), ivec3(2,2,2))) ==
		Box(ivec3(1,1,1), ivec3(1,1,1)));
	assert(boxIntersection(
		Box(ivec3(1,1,1), ivec3(1,1,1)),
		Box(ivec3(1,1,1), ivec3(1,1,1))) ==
		Box(ivec3(1,1,1), ivec3(1,1,1)));
	assert(boxIntersection(
		Box(ivec3(0,0,0), ivec3(2,2,2)),
		Box(ivec3(0,0,-1), ivec3(2,2,2))) ==
		Box(ivec3(0,0,0), ivec3(2,2,1)));
	assert(boxIntersection(
		Box(ivec3(1,0,0), ivec3(1,1,1)),
		Box(ivec3(0,0,0), ivec3(32,32,32))) ==
		Box(ivec3(1,0,0), ivec3(1,1,1)));
}

Box calcCommonBox(Box[] boxes ...)
{
	ivec3 start = boxes[0].position;
	ivec3 end = boxes[0].endPosition;

	foreach(box; boxes[1..$])
	{
		start.x = alg_min(start.x, box.position.x);
		start.y = alg_min(start.y, box.position.y);
		start.z = alg_min(start.z, box.position.z);

		end.x = alg_max(end.x, box.endPosition.x);
		end.y = alg_max(end.y, box.endPosition.y);
		end.z = alg_max(end.z, box.endPosition.z);
	}

	return boxFromCorners(start, end);
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
