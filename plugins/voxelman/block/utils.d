/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.block.utils;

import std.array : Appender;
import dlib.math.vector : vec3, ivec3;
import voxelman.storage.coordinates;

enum Side : ubyte
{
	north	= 0,
	south	= 1,

	east	= 2,
	west	= 3,

	top		= 4,
	bottom	= 5,
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
	float randomTint = uniform(0.92f, 1.0f, rnd);

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
