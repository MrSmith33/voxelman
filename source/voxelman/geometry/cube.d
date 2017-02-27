/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.geometry.cube;

import voxelman.math : ivec3;

enum CubeSide : ubyte
{
	zneg = 0,
	zpos = 1,

	xpos = 2,
	xneg = 3,

	ypos = 4,
	yneg = 5,
}

enum SideMask : ubyte
{
	zneg = 0b_00_0001,
	zpos = 0b_00_0010,

	xpos = 0b_00_0100,
	xneg = 0b_00_1000,

	ypos = 0b_01_0000,
	yneg = 0b_10_0000,
}

enum CubeCorner : ubyte
{
	xneg_yneg_zneg,
	xpos_yneg_zneg,
	xneg_yneg_zpos,
	xpos_yneg_zpos,

	xneg_ypos_zneg,
	xpos_ypos_zneg,
	xneg_ypos_zpos,
	xpos_ypos_zpos,
}

// In the same order as CubeSide, sideOffsets26
enum Dir27 : ubyte
{
	// 6 adjacent
	zneg, // [ 0, 0,-1]
	zpos, // [ 0, 0, 1]
	xpos, // [ 1, 0, 0]
	xneg, // [-1, 0, 0]
	ypos, // [ 0, 1, 0]
	yneg, // [ 0,-1, 0]

	// bottom 8
	xneg_yneg_zneg,	// [-1,-1,-1]
	     yneg_zneg, // [ 0,-1,-1]
	xpos_yneg_zneg, // [ 1,-1,-1]
	xneg_yneg     , // [-1,-1, 0]
	xpos_yneg     , // [ 1,-1, 0]
	xneg_yneg_zpos, // [-1,-1, 1]
	     yneg_zpos, // [ 0,-1, 1]
	xpos_yneg_zpos, // [ 1,-1, 1]

	// middle 4
	xneg_zneg, // [-1, 0,-1]
	xpos_zneg, // [ 1, 0,-1]
	xneg_zpos, // [-1, 0, 1]
	xpos_zpos, // [ 1, 0, 1]

	// top 8
	xneg_ypos_zneg,	// [-1, 1,-1]
	     ypos_zneg,	// [ 0, 1,-1]
	xpos_ypos_zneg,	// [ 1, 1,-1]
	xneg_ypos     ,	// [-1, 1, 0]
	xpos_ypos     ,	// [ 1, 1, 0]
	xneg_ypos_zpos,	// [-1, 1, 1]
	     ypos_zpos,	// [ 0, 1, 1]
	xpos_ypos_zpos,	// [ 1, 1, 1]

	central
}

immutable Dir27[27] dirs3by3 = [
	// bottom 9
	Dir27.xneg_yneg_zneg, // [-1,-1,-1]
	Dir27.yneg_zneg     , // [ 0,-1,-1]
	Dir27.xpos_yneg_zneg, // [ 1,-1,-1]

	Dir27.xneg_yneg     , // [-1,-1, 0]
	Dir27.     yneg     , // [ 0,-1, 0]
	Dir27.xpos_yneg     , // [ 1,-1, 0]

	Dir27.xneg_yneg_zpos, // [-1,-1, 1]
	Dir27.     yneg_zpos, // [ 0,-1, 1]
	Dir27.xpos_yneg_zpos, // [ 1,-1, 1]

	// middle 9
	Dir27.xneg_zneg     , // [-1, 0,-1]
	Dir27.          zneg, // [ 0, 0,-1]
	Dir27.xpos_zneg     , // [ 1, 0,-1]

	Dir27.xneg          , // [-1, 0, 0]
	Dir27.   central    , // [ 0, 0, 0]
	Dir27.xpos          , // [ 1, 0, 0]

	Dir27.xneg_zpos     , // [-1, 0, 1]
	Dir27.          zpos, // [ 0, 0, 1]
	Dir27.xpos_zpos     , // [ 1, 0, 1]

	// top 9
	Dir27.xneg_ypos_zneg, // [-1, 1,-1]
	Dir27.     ypos_zneg, // [ 0, 1,-1]
	Dir27.xpos_ypos_zneg, // [ 1, 1,-1]

	Dir27.xneg_ypos     , // [-1, 1, 0]
	Dir27.     ypos     , // [ 0, 1, 0]
	Dir27.xpos_ypos     , // [ 1, 1, 0]

	Dir27.xneg_ypos_zpos, // [-1, 1, 1]
	Dir27.     ypos_zpos, // [ 0, 1, 1]
	Dir27.xpos_ypos_zpos, // [ 1, 1, 1]
];

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

CubeSide sideFromNormal(ivec3 normal)
{
	if (normal.x == 1)
		return CubeSide.xpos;
	else if (normal.x == -1)
		return CubeSide.xneg;

	if (normal.y == 1)
		return CubeSide.ypos;
	else if (normal.y == -1)
		return CubeSide.yneg;

	if (normal.z == 1)
		return CubeSide.zpos;
	else if (normal.z == -1)
		return CubeSide.zneg;

	return CubeSide.zneg;
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
	1, 0, 0, // triangle 1 : begin // zneg
	0, 1, 0,
	1, 1, 0, // triangle 1 : end
	1, 0, 0, // triangle 2 : begin
	0, 0, 0,
	0, 1, 0, // triangle 2 : end

	0, 0, 1, // zpos
	1, 1, 1,
	0, 1, 1,
	0, 0, 1,
	1, 0, 1,
	1, 1, 1,

	1, 0, 1, // xpos
	1, 1, 0,
	1, 1, 1,
	1, 0, 1,
	1, 0, 0,
	1, 1, 0,

	0, 0, 0, // xneg
	0, 1, 1,
	0, 1, 0,
	0, 0, 0,
	0, 0, 1,
	0, 1, 1,

	0, 1, 1, // ypos
	1, 1, 0,
	0, 1, 0,
	0, 1, 1,
	1, 1, 1,
	1, 1, 0,

	1, 0, 1, // yneg
	0, 0, 0,
	1, 0, 0,
	1, 0, 1,
	0, 0, 1,
	0, 0, 0,
];

immutable ubyte[6] faceCornerIndexes = [1, 3, 0, 1, 2, 3];
immutable ubyte[6] flippedFaceCornerIndexes = [1, 2, 0, 0, 2, 3];

// the "Y" of 1 and 3 vertex are inversed
immutable ubyte[18 * 6] flippedCubeFaces =
[
	1, 0, 0, // triangle 1 : begin // zneg
	0, 0, 0,
	1, 1, 0, // triangle 1 : end
	1, 1, 0, // triangle 2 : begin
	0, 0, 0,
	0, 1, 0, // triangle 2 : end

	0, 0, 1, // zpos
	1, 0, 1,
	0, 1, 1,
	0, 1, 1,
	1, 0, 1,
	1, 1, 1,

	1, 0, 1, // xpos
	1, 0, 0,
	1, 1, 1,
	1, 1, 1,
	1, 0, 0,
	1, 1, 0,

	0, 0, 0, // xneg
	0, 0, 1,
	0, 1, 0,
	0, 1, 0,
	0, 0, 1,
	0, 1, 1,

	0, 1, 1, // ypos
	1, 1, 1,
	0, 1, 0,
	0, 1, 0,
	1, 1, 1,
	1, 1, 0,

	1, 0, 1, // yneg
	0, 0, 1,
	1, 0, 0,
	1, 0, 0,
	0, 0, 1,
	0, 0, 0,
];

immutable ubyte[3][8] cubeVerticies = [
	[0,0,0], // 0
	[1,0,0], // 1
	[0,0,1], // 2
	[1,0,1], // 3
	[0,1,0], // 4
	[1,1,0], // 5
	[0,1,1], // 6
	[1,1,1], // 7
];

// 6 sides by 4 indices per side
immutable ubyte[4][6] cubeSideVertIndices = [
	[5,1,0,4], // zneg
	[6,2,3,7], // zpos
	[7,3,1,5], // xpos
	[4,0,2,6], // xneg
	[4,6,7,5], // ypos
	[1,3,2,0], // yneg
];

immutable ubyte[36] cubeFullTriIndicies = [
	1, 4, 5, 1, 0, 4, // zneg
	2, 7, 6, 2, 3, 7, // zpos
	3, 5, 7, 3, 1, 5, // xpos
	0, 6, 4, 0, 2, 6, // xneg
	6, 5, 4, 6, 7, 5, // ypos
	3, 0, 1, 3, 2, 0, // yneg
];
