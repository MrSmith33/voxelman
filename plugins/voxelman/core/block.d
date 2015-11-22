/**
Copyright: Copyright (c) 2013-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.core.block;

import voxelman.core.config;


struct Block
{
	BlockType id;
	string name;
	ubyte[3] color;
	bool isVisible;

	ubyte[] mesh(ubyte bx, ubyte by, ubyte bz, ubyte sides, ubyte sidesnum) const
	{
		return getMesh(this, bx, by, bz, sides, sidesnum);
	}

	bool function (Side side) isSideTransparent;
	ubyte[] function(const Block block,
		ubyte bx, ubyte by, ubyte bz, ubyte sides, ubyte sidesnum) getMesh;
}

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
