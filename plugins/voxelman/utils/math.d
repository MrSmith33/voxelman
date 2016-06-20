/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.utils.math;

public import dlib.math.vector;
public import dlib.math.utils;
import std.traits : isFloatingPoint;
public import std.math : isNaN, floor;

void nansToZero(T, int size)(ref Vector!(T, size) vector)
	if (isFloatingPoint!T)
{
	foreach(ref item; vector.arrayof)
	{
		item = isNaN(item) ? 0 : item;
	}
}

void nansToZero(T, int size)(ref T[size] vector)
	if (isFloatingPoint!T)
{
	foreach(ref item; vector)
	{
		item = isNaN(item) ? 0 : item;
	}
}
