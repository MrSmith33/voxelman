/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.mesh.sidemeshers.slope;

import voxelman.log;
import voxelman.container.buffer;
import voxelman.math;
import voxelman.geometry.cube;

import voxelman.world.block;
import voxelman.world.mesh.chunkmesh;

import voxelman.world.mesh.sidemeshers.utils;

void meshSlopeSideOccluded(CubeSide side, ubyte[4] cornerOcclusion, SideParams d)
{
	immutable float mult = shadowMultipliers[side];

	// apply fake lighting
	float r = mult * d.color.r;
	float g = mult * d.color.g;
	float b = mult * d.color.b;

	// Ambient occlusion multipliers
	float vert0AoMult = occlusionTable[cornerOcclusion[0]];
	float vert1AoMult = occlusionTable[cornerOcclusion[1]];
	float vert2AoMult = occlusionTable[cornerOcclusion[2]];
	float vert3AoMult = occlusionTable[cornerOcclusion[3]];

	immutable ubyte[3][4] finalColors = [
		[cast(ubyte)(vert0AoMult * r), cast(ubyte)(vert0AoMult * g), cast(ubyte)(vert0AoMult * b)],
		[cast(ubyte)(vert1AoMult * r), cast(ubyte)(vert1AoMult * g), cast(ubyte)(vert1AoMult * b)],
		[cast(ubyte)(vert2AoMult * r), cast(ubyte)(vert2AoMult * g), cast(ubyte)(vert2AoMult * b)],
		[cast(ubyte)(vert3AoMult * r), cast(ubyte)(vert3AoMult * g), cast(ubyte)(vert3AoMult * b)]];

	ubyte[3] indicies = slopeFaceCornerIndexes[d.rotation][side];
	//ubyte[3] colorIndicies = slopeFaceCornerColorIndexes[side];
	ubyte[3] colorIndicies = slopeFaceCornerColorIndexes[d.rotation];
	d.buffer.put(
		cast(MeshVertex)MeshVertex2(
			cubeVerticies[indicies[0]][0] + d.blockPos.x,
			cubeVerticies[indicies[0]][1] + d.blockPos.y,
			cubeVerticies[indicies[0]][2] + d.blockPos.z,
			finalColors[colorIndicies[0]]),
		cast(MeshVertex)MeshVertex2(
			cubeVerticies[indicies[1]][0] + d.blockPos.x,
			cubeVerticies[indicies[1]][1] + d.blockPos.y,
			cubeVerticies[indicies[1]][2] + d.blockPos.z,
			finalColors[colorIndicies[1]]),
		cast(MeshVertex)MeshVertex2(
			cubeVerticies[indicies[2]][0] + d.blockPos.x,
			cubeVerticies[indicies[2]][1] + d.blockPos.y,
			cubeVerticies[indicies[2]][2] + d.blockPos.z,
			finalColors[colorIndicies[2]])
	);
}

immutable ubyte[3][6] slopeColorIndexesFromRotation = [
	[1,3,0], [1,2,0], [1,2,3], [0,2,3]];

immutable ubyte[3][6] slopeFaceCornerColorIndexes = [
	// zneg
	[1, 3, 0], // zneg
	[1, 3, 0], // zpos
	[1, 2, 3], // xpos valid TODO other
	[0, 1, 2], // xneg valid TODO other
	[1, 3, 0], // ypos
	[1, 3, 0]]; // yneg

// 0--3 // corner numbering of face verticies
// |  |
// 1--2
// 2-1  2      2  0-2
// |/   |\    /|   \|
// 0    0-1  0-1    1
//
//  0    1    2    3  rotation
// CCW
// slopeFaceCornerIndexes[rotation,4][side,6][x/y/z,3]
immutable ubyte[3][6][4] slopeFaceCornerIndexes =
[	// zneg    zpos    xpos    xneg    ypos    yneg
	[[1,4,5],[2,7,6],[3,5,7],[0,6,4],[6,5,4],[3,0,1],], // rotation 0
	[[1,0,5],[2,3,6],[3,1,7],[0,2,4],[6,7,4],[3,2,1],], // rotation 1
	[[1,0,4],[2,3,7],[3,1,5],[0,2,6],[6,7,5],[3,2,0],], // rotation 2
	[[5,0,4],[6,3,7],[7,1,5],[4,2,6],[4,7,5],[1,2,0],], // rotation 3
];
