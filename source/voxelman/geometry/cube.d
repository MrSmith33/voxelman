/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.geometry.cube;

enum CubeSide : ubyte
{
	zneg = 0,
	zpos = 1,

	xpos = 2,
	xneg = 3,

	ypos = 4,
	yneg = 5,
}


immutable CubeSide[6] oppSide = [
	CubeSide.zpos,
	CubeSide.zneg,
	CubeSide.xneg,
	CubeSide.xpos,
	CubeSide.yneg,
	CubeSide.ypos];

template sideOffsets(size_t numAdjacent) {
	static if (numAdjacent == 6)
		alias sideOffsets = sideOffsets6;
	else static if (numAdjacent == 26)
		alias sideOffsets = sideOffsets26;
}

// does not include center
immutable byte[3][26] sideOffsets26 = [
	// 6 adjacent
	[ 0, 0,-1],
	[ 0, 0, 1],
	[ 1, 0, 0],
	[-1, 0, 0],
	[ 0, 1, 0],
	[ 0,-1, 0],

	// bottom 8
	[-1,-1,-1],
	[ 0,-1,-1],
	[ 1,-1,-1],
	[-1,-1, 0],
	[ 1,-1, 0],
	[-1,-1, 1],
	[ 0,-1, 1],
	[ 1,-1, 1],

	// middle 4
	[-1, 0,-1],
	[ 1, 0,-1],
	[-1, 0, 1],
	[ 1, 0, 1],

	// top 8
	[-1, 1,-1],
	[ 0, 1,-1],
	[ 1, 1,-1],
	[-1, 1, 0],
	[ 1, 1, 0],
	[-1, 1, 1],
	[ 0, 1, 1],
	[ 1, 1, 1],
];

immutable byte[3][27] offsets3by3 = [
	// bottom 9
	[-1,-1,-1],
	[ 0,-1,-1],
	[ 1,-1,-1],

	[-1,-1, 0],
	[ 0,-1, 0],
	[ 1,-1, 0],

	[-1,-1, 1],
	[ 0,-1, 1],
	[ 1,-1, 1],

	// middle 9
	[-1, 0,-1],
	[ 0, 0,-1],
	[ 1, 0,-1],

	[-1, 0, 0],
	[ 0, 0, 0],
	[ 1, 0, 0],

	[-1, 0, 1],
	[ 0, 0, 1],
	[ 1, 0, 1],

	// top 9
	[-1, 1,-1],
	[ 0, 1,-1],
	[ 1, 1,-1],

	[-1, 1, 0],
	[ 0, 1, 0],
	[ 1, 1, 0],

	[-1, 1, 1],
	[ 0, 1, 1],
	[ 1, 1, 1],
];

// does not include center and other 20 adjacent
immutable byte[3][6] sideOffsets6 = sideOffsets26[0..6];
immutable byte[3][20] sideOffsets20 = sideOffsets26[6..26];

// mesh for single block
immutable ubyte[18 * 6] cubeFaces =
[
	0, 0, 0, // triangle 1 : begin // zneg
	1, 1, 0,
	1, 0, 0, // triangle 1 : end
	0, 0, 0, // triangle 2 : begin
	0, 1, 0,
	1, 1, 0, // triangle 2 : end

	1, 0, 1, // zpos
	0, 1, 1,
	0, 0, 1,
	1, 0, 1,
	1, 1, 1,
	0, 1, 1,

	1, 0, 0, // xpos
	1, 1, 1,
	1, 0, 1,
	1, 0, 0,
	1, 1, 0,
	1, 1, 1,

	0, 0, 1, // xneg
	0, 1, 0,
	0, 0, 0,
	0, 0, 1,
	0, 1, 1,
	0, 1, 0,

	1, 1, 1, // ypos
	0, 1, 0,
	0, 1, 1,
	1, 1, 1,
	1, 1, 0,
	0, 1, 0,

	0, 0, 1, // yneg
	1, 0, 0,
	1, 0, 1,
	0, 0, 1,
	0, 0, 0,
	1, 0, 0,
];
