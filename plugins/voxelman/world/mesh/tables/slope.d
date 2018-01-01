/**
Copyright: Copyright (c) 2017-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.mesh.tables.slope;

import voxelman.geometry;
import voxelman.world.block.shape;

private alias SSM = ShapeSideMask;
BlockShape[12] metaToShapeTable = [
	//zneg        zpos        xpos        xneg        ypos       yneg
	{[SSM.full,   SSM.empty,  SSM.slope2, SSM.slope1, SSM.empty,  SSM.full  ], 0b_0011_1111, true, true}, // 0, yneg full
	{[SSM.slope1, SSM.slope2, SSM.full,   SSM.empty,  SSM.empty,  SSM.full  ], 0b_1010_1111, true, true}, // 1
	{[SSM.empty,  SSM.full,   SSM.slope1, SSM.slope2, SSM.empty,  SSM.full  ], 0b_1100_1111, true, true}, // 2
	{[SSM.slope2, SSM.slope1, SSM.empty,  SSM.full,   SSM.empty,  SSM.full  ], 0b_0101_1111, true, true}, // 3

	// looking from ypos, use face corners for numbering | vertical sides full
	{[SSM.full,   SSM.empty,  SSM.empty,  SSM.full,   SSM.slope0, SSM.slope3], 0b_0111_0111, true, true}, // 0 zneg, xneg full
	{[SSM.empty,  SSM.full,   SSM.empty,  SSM.full,   SSM.slope1, SSM.slope2], 0b_1101_1101, true, true}, // 1 zpos, xneg full
	{[SSM.empty,  SSM.full,   SSM.full,   SSM.empty,  SSM.slope2, SSM.slope1], 0b_1110_1110, true, true}, // 2 zpos, xpos full
	{[SSM.full,   SSM.empty,  SSM.full,   SSM.empty,  SSM.slope3, SSM.slope0], 0b_1011_1011, true, true}, // 3 zneg, xpos full

	{[SSM.full,   SSM.empty,  SSM.slope3, SSM.slope0, SSM.full,   SSM.empty ], 0b_1111_0011, true, true}, // 0, ypos full
	{[SSM.slope0, SSM.slope3, SSM.full,   SSM.empty,  SSM.full,   SSM.empty ], 0b_1111_1010, true, true}, // 1
	{[SSM.empty,  SSM.full,   SSM.slope0, SSM.slope3, SSM.full,   SSM.empty ], 0b_1111_1100, true, true}, // 2
	{[SSM.slope3, SSM.slope0, SSM.empty,  SSM.full,   SSM.full,   SSM.empty ], 0b_1111_0101, true, true}, // 3
];

// 0--3 occlusion side 1
// |  |
// 1--2 occlusion side 2
// metadata[12], side * corner index[4]
immutable ubyte[4][12] slopeInternalOcclusionIndicies = [
	[0,3,1,2],[3,2,1,2],[2,1,1,2],[1,0,1,2],
	[3,2,0,1],[3,2,0,1],[3,2,0,1],[3,2,0,1],
	[0,3,3,0],[0,3,0,1],[0,3,1,2],[0,3,2,3],
];

// internal geometry
immutable ubyte[4][12] slopeInternalIndicies = [
	[4,2,3,5],
	[5,0,2,7],
	[7,1,0,6],
	[6,3,1,4],

	[5,6,2,1],
	[4,7,3,0],
	[6,5,1,2],
	[7,4,0,3],

	[6,0,1,7],
	[4,1,3,6],
	[5,3,2,4],
	[7,2,0,5],
];

// corners are fetched from those sides via slopeInternalOcclusionIndicies
immutable CubeSide[2][12] slopeOcclusionSides = [
	[CubeSide.ypos, CubeSide.zpos],
	[CubeSide.ypos, CubeSide.xneg],
	[CubeSide.ypos, CubeSide.zneg],
	[CubeSide.ypos, CubeSide.xpos],

	[CubeSide.xpos, CubeSide.zpos],
	[CubeSide.zneg, CubeSide.xpos],
	[CubeSide.xneg, CubeSide.zneg],
	[CubeSide.zpos, CubeSide.xneg],

	[CubeSide.zpos, CubeSide.yneg],
	[CubeSide.xneg, CubeSide.yneg],
	[CubeSide.zneg, CubeSide.yneg],
	[CubeSide.xpos, CubeSide.yneg],
];

immutable ubyte[3][4] slopeColorIndicies = [ // from rotation
	[1,3,0], [1,2,0], [1,2,3], [0,2,3]];

// 0--3 // corner numbering of face verticies
// |  |
// 1--2
// 2-1  2      2  0-2
// |/   |\    /|   \|
// 0    0-1  0-1    1
//
//  0    1    2    3  rotation
// CCW
// slopeFaceCornerIndicies[rotation,4][side,6][x/y/z,3]
immutable ubyte[3][6][4] slopeFaceIndicies = // from rotation and side
[	// zneg    zpos    xpos    xneg    ypos    yneg
	[[1,4,5],[2,7,6],[3,5,7],[0,6,4],[6,5,4],[3,0,1],], // rotation 0
	[[1,0,5],[2,3,6],[3,1,7],[0,2,4],[6,7,4],[3,2,1],], // rotation 1
	[[1,0,4],[2,3,7],[3,1,5],[0,2,6],[6,7,5],[3,2,0],], // rotation 2
	[[5,0,4],[6,3,7],[7,1,5],[4,2,6],[4,7,5],[1,2,0],], // rotation 3
];

// each side includes 4 rotations that have this side as full.
immutable ubyte[4][6] slopeSideRotations = [
	[ 0, 4, 8, 7], // zneg (yneg, xneg, ypos, xpos)
	[ 2, 6,10, 5], // zpos (yneg, xpos, ypos, xneg)
	[ 1, 7, 9, 6], // xpos (yneg, zneg, ypos, zpos)
	[ 3, 5,11, 4], // xneg (yneg, zpos, ypos, zneg)
	[10,11, 8, 9], // ypos (zpos, xneg, zneg, xpos)
	[ 2, 3, 0, 1], // yneg (zpos, xneg, zneg, xpos)
];
