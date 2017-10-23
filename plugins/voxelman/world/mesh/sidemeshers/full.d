/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.world.mesh.sidemeshers.full;

import voxelman.container.buffer;
import voxelman.math;
import voxelman.geometry;

import voxelman.world.block;
import voxelman.world.mesh.chunkmesh;

import voxelman.world.mesh.sidemeshers.utils;

void meshFullSideOccluded(CubeSide side, ubyte[4] cornerOcclusion, SideParams d)
{
	immutable float mult = shadowMultipliers[side];
	float[3] color = [mult * d.color.r, mult * d.color.g, mult * d.color.b];

	meshOccludedQuad(*d.buffer, cornerOcclusion, color, d.blockPos,
		cubeSideVertIndices[side], cubeVerticies.ptr);
}

void meshFullSideOccluded2(CubeSide side, ubyte[4] cornerOcclusion, SideParams d)
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

	const(ubyte)[] faces;
	const(ubyte)[] faceIndexes;

	if(vert0AoMult + vert2AoMult > vert1AoMult + vert3AoMult)
	{
		faces = flippedCubeFaces[];
		faceIndexes = flippedFaceCornerIndexes[];
	}
	else
	{
		faces = cubeFaces[];
		faceIndexes = faceCornerIndexes[];
	}

	d.buffer.put(
		MeshVertex(
			faces[18*side  ] + d.blockPos.x,
			faces[18*side+1] + d.blockPos.y,
			faces[18*side+2] + d.blockPos.z,
			finalColors[faceIndexes[0]]),
		MeshVertex(
			faces[18*side+3] + d.blockPos.x,
			faces[18*side+4] + d.blockPos.y,
			faces[18*side+5] + d.blockPos.z,
			finalColors[faceIndexes[1]]),
		MeshVertex(
			faces[18*side+6] + d.blockPos.x,
			faces[18*side+7] + d.blockPos.y,
			faces[18*side+8] + d.blockPos.z,
			finalColors[faceIndexes[2]]),
		MeshVertex(
			faces[18*side+9] + d.blockPos.x,
			faces[18*side+10] + d.blockPos.y,
			faces[18*side+11] + d.blockPos.z,
			finalColors[faceIndexes[3]]),
		MeshVertex(
			faces[18*side+12] + d.blockPos.x,
			faces[18*side+13] + d.blockPos.y,
			faces[18*side+14] + d.blockPos.z,
			finalColors[faceIndexes[4]]),
		MeshVertex(
			faces[18*side+15] + d.blockPos.x,
			faces[18*side+16] + d.blockPos.y,
			faces[18*side+17] + d.blockPos.z,
			finalColors[faceIndexes[5]])
	);
}
