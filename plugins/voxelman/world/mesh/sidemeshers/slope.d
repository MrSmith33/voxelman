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

import voxelman.world.mesh.config;
import voxelman.world.mesh.sidemeshers.utils;
import voxelman.world.mesh.tables.slope;

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

	static if (AO_DEBUG_ENABLED)
		immutable ubyte[3][4] finalColors = getDebugAOColors(cornerOcclusion);
	else
		immutable ubyte[3][4] finalColors = [
			[cast(ubyte)(vert0AoMult * r), cast(ubyte)(vert0AoMult * g), cast(ubyte)(vert0AoMult * b)],
			[cast(ubyte)(vert1AoMult * r), cast(ubyte)(vert1AoMult * g), cast(ubyte)(vert1AoMult * b)],
			[cast(ubyte)(vert2AoMult * r), cast(ubyte)(vert2AoMult * g), cast(ubyte)(vert2AoMult * b)],
			[cast(ubyte)(vert3AoMult * r), cast(ubyte)(vert3AoMult * g), cast(ubyte)(vert3AoMult * b)]];

	ubyte[3] indicies = slopeFaceIndicies[d.rotation][side];
	ubyte[3] colorIndicies = slopeColorIndicies[d.rotation];
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
