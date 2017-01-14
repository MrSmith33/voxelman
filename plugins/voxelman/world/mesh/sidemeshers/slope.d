/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.mesh.sidemeshers.slope;

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

	d.buffer.put(
		cast(MeshVertex)MeshVertex2(
			slopeFaces[9*side  ] + d.blockPos.x,
			slopeFaces[9*side+1] + d.blockPos.y,
			slopeFaces[9*side+2] + d.blockPos.z,
			finalColors[slopeFaceCornerIndexes[side][0]]),
		cast(MeshVertex)MeshVertex2(
			slopeFaces[9*side+3] + d.blockPos.x,
			slopeFaces[9*side+4] + d.blockPos.y,
			slopeFaces[9*side+5] + d.blockPos.z,
			finalColors[slopeFaceCornerIndexes[side][1]]),
		cast(MeshVertex)MeshVertex2(
			slopeFaces[9*side+6] + d.blockPos.x,
			slopeFaces[9*side+7] + d.blockPos.y,
			slopeFaces[9*side+8] + d.blockPos.z,
			finalColors[slopeFaceCornerIndexes[side][2]])
	);
}

immutable ubyte[3][6] slopeFaceCornerIndexes = [
	[1, 3, 0], // zneg
	[1, 3, 0], // zpos
	[1, 2, 3], // xpos valid TODO other
	[0, 1, 2], // xneg valid TODO other
	[1, 3, 0], // ypos
	[1, 3, 0]]; // yneg

// mesh for single block
immutable ubyte[9 * 6] slopeFaces =
[
	1, 0, 0, // triangle 1 : begin // zneg
	0, 1, 0,
	1, 1, 0, // triangle 1 : end

	0, 0, 1, // zpos
	1, 1, 1,
	0, 1, 1,

	1, 0, 1, // xpos
	1, 0, 0,
	1, 1, 0,

	0, 1, 0, // xneg
	0, 0, 0,
	0, 0, 1,

	0, 1, 1, // ypos
	1, 1, 0,
	0, 1, 0,

	1, 0, 1, // yneg
	0, 0, 0,
	1, 0, 0,
];

// internal geometry
immutable ubyte[4] slopeIntIndexes = [4, 2, 3, 5];
