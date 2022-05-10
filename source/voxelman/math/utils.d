/**
Copyright: Copyright (c) 2015-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.math.utils;

import std.traits : isFloatingPoint;
import voxelman.math;
import std.algorithm : std_clamp = clamp;
import dlib.math.utils : isConsiderZero;

Vector!(T, n) abs(T, size_t n)(Vector!(T, n) vector) pure nothrow
{
	Vector!(T, n) result;
	foreach(i, elem; vector.arrayof)
		result[i] = elem < 0 ? -elem : elem;
	return result;
}

enum Alignment
{
	min,
	center,
	max
}

/// Returns offset to add to object position
T alignOnAxis(T)(T objSize, Alignment alignment, T areaSize)
{
	final switch (alignment)
	{
		case Alignment.min: return 0;
		case Alignment.center: return areaSize/2 - objSize/2;
		case Alignment.max: return areaSize - objSize;
	}
}

bool toggle_bool(ref bool value)
{
	return value = !value;
}

T set_flag(T)(T bits, bool flagValue, T flagBit)
{
	if (flagValue)
		return bits | flagBit;
	else
		return bits & (~flagBit);
}

T toggle_flag(T)(T bits, T flagBit)
{
	return bits ^ flagBit;
}

T divCeil(T)(T a, T b)
{
	return a / b + (a % b > 0);
}

T distance(T) (Vector!(T,2) a, Vector!(T,2) b)
{
	T dx = a.x - b.x;
	T dy = a.y - b.y;
	return sqrt((dx * dx) + (dy * dy));
}

bool isAlmostZero(Vector2f v)
{
	return (isConsiderZero(v.x) &&
			isConsiderZero(v.y));
}

Vector!(T, n) vector_clamp(T, size_t n)(Vector!(T, n) vector, Vector!(T, n) lower, Vector!(T, n) upper) pure nothrow
{
	Vector!(T, n) result;
	foreach(i, ref elem; result.arrayof)
		elem = std_clamp(vector.arrayof[i], lower.arrayof[i], upper.arrayof[i]);
	return result;
}

Vector!(T, n) vector_min(T, size_t n)(Vector!(T, n) a, Vector!(T, n) b) pure nothrow
{
	Vector!(T, n) result;
	foreach(i, ref elem; result.arrayof)
		elem = min(a.arrayof[i], b.arrayof[i]);
	return result;
}

Vector!(T, n) vector_max(T, size_t n)(Vector!(T, n) a, Vector!(T, n) b) pure nothrow
{
	Vector!(T, n) result;
	foreach(i, ref elem; result.arrayof)
		elem = max(a.arrayof[i], b.arrayof[i]);
	return result;
}

void nansToZero(T, int size)(ref Vector!(T, size) vector) pure nothrow
	if (isFloatingPoint!T)
{
	foreach(ref item; vector.arrayof)
	{
		item = isNaN(item) ? 0 : item;
	}
}

void nansToZero(T, int size)(ref T[size] vector) pure nothrow
	if (isFloatingPoint!T)
{
	foreach(ref item; vector)
	{
		item = isNaN(item) ? 0 : item;
	}
}

T nextPOT(T)(T x)
{
	--x;
	x |= x >> 1;  // handle  2 bit numbers
	x |= x >> 2;  // handle  4 bit numbers
	x |= x >> 4;  // handle  8 bit numbers
	static if (T.sizeof >= 2) x |= x >> 8;  // handle 16 bit numbers
	static if (T.sizeof >= 4) x |= x >> 16; // handle 32 bit numbers
	static if (T.sizeof >= 8) x |= x >> 32; // handle 64 bit numbers
	++x;

	return x;
}

unittest {
	assert(nextPOT(1) == 1);
	assert(nextPOT(2) == 2);
	assert(nextPOT(3) == 4);
	assert(nextPOT(4) == 4);
	assert(nextPOT(5) == 8);
	assert(nextPOT(10) == 16);
	assert(nextPOT(30) == 32);
	assert(nextPOT(250) == 256);
	assert(nextPOT(514) == 1024);
	assert(nextPOT(1<<15+1) == 1<<16);
	assert(nextPOT(1UL<<31+1) == 1UL<<32);
	assert(nextPOT(1UL<<49+1) == 1UL<<50);
}

V lerpMovement(V)(V from, V to, double speed, double dt)
{
	auto curDist = distance(from, to);
	auto distanceToMove = speed * dt;
	if (curDist == 0 || distanceToMove == 0) return from;
	double time = distanceToMove / curDist;
	return lerpClamp(from, to, time);
}

V lerpClamp(V)(V currentPos, V targetPos, double time)
{
	time = clamp(time, 0.0, 1.0);
	return lerp(currentPos, targetPos, time);
}
