/**
Copyright: Copyright (c) 2013-2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.block;


alias BlockType = ubyte;

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