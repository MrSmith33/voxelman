/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module railroad.rail.mesh;

import voxelman.log;
import std.range;
import std.conv : to;
import voxelman.container.buffer;
import voxelman.math;

import voxelman.model.vertex;
import voxelman.graphics;
import voxelman.geometry;

import voxelman.world.mesh.chunkmesh;
import voxelman.world.mesh.sidemeshers.full;
import voxelman.world.mesh.sidemeshers.utils;
import voxelman.world.block;
import voxelman.world.blockentity.blockentityaccess;
import voxelman.world.blockentity.blockentitydata;
import voxelman.world.blockentity.utils;

import railroad.rail.utils;

void makeRailMesh(BlockEntityMeshingData meshingData)
{
	auto railData = RailData(meshingData.data);
	if (meshingData.data.type == BlockEntityType.localBlockEntity &&
		meshingData.entityPos == ivec3(0,0,0))
	{
		putRailMesh!MeshVertex(
			meshingData.output[Solidity.solid],
			meshingData.chunkPos,
			railData);
	}

	if (railData.isSlope)
	{
		CubeSide sideToMesh;
		if (isSlopeUpSideBlock(railData, meshingData.entityPos, sideToMesh))
		{
			if (meshingData.sides & (1 << sideToMesh))
			{
				ubyte[4] occlusions = meshingData.occlusionHandler(meshingData.blockIndex, sideToMesh);
				SideParams sideParams = SideParams(
					ubvec3(meshingData.chunkPos),
					calcColor(meshingData.blockIndex, meshingData.color),
					[0,0],
					0,
					&meshingData.output[Solidity.solid]);
				meshFullSideOccluded(sideToMesh, occlusions, sideParams);
			}
		}
	}

	if (meshingData.sides & SideMask.yneg)
	{
		ubyte[4] occlusions = meshingData.occlusionHandler(meshingData.blockIndex, CubeSide.yneg);
		SideParams sideParams = SideParams(
			ubvec3(meshingData.chunkPos),
			calcColor(meshingData.blockIndex, meshingData.color),
			[0,0],
			0,
			&meshingData.output[Solidity.solid]);
		meshFullSideOccluded(CubeSide.yneg, occlusions, sideParams);
	}
}

void putRailMesh(Vert, Sink)(ref Sink sink, ivec3 chunkPos, RailData data)
{
	ivec3 tilePos = railTilePos(chunkPos);
	auto chunkPosF = vec3(tilePos);

	foreach(segment; data.getSegments())
	{
		auto meshIndex = railSegmentMeshId[segment];
		auto mesh = railMeshes[meshIndex];
		ubyte rotation = railSegmentMeshRotation[segment];
		auto rotator = getCCWRotationShiftOriginFunction!vec3(rotation);
		vec3 offset = chunkPosF + vec3(railSegmentOffsets[segment]);
		vec3 meshSize = vec3(meshSizes[meshIndex]);

		sink.reserve(mesh.length);

		foreach(v; mesh)
		{
			vec3 pos = rotator(v.position, meshSize) + offset;
			sink.put(Vert(pos, [0,0], v.color.r));
		}
	}
}

alias RailVertexT = VertexPosColor!(float, 3, ubyte, 3);
__gshared RailVertexT[][3] railMeshes;
ivec3[3] meshSizes = [
	ivec3(4, 1, 8),
	ivec3(6, 1, 6),
	ivec3(4, 1, 8)];


void putRailPreview(
	ref Buffer!ColoredVertex buffer,
	RailPos railPos0, RailPos railPos1,
	CubeSide side0, CubeSide side1,
	bool flipEndOffset,
	Colors color)
{
	assert(side0 < 4);
	assert(side1 < 4);
	vec3 startOff = vec3(railPos0.x * RAIL_TILE_SIZE, railPos0.y, railPos0.z * RAIL_TILE_SIZE);
	vec3 endOff = vec3(railPos1.x * RAIL_TILE_SIZE, railPos1.y, railPos1.z * RAIL_TILE_SIZE);

	vec3[4] sideOffsets = [
		vec3(RAIL_TILE_SIZE/2-0.25, 0, 0), // zneg
		vec3(RAIL_TILE_SIZE/2-0.25, 0, RAIL_TILE_SIZE-0.5), // zpos
		vec3(RAIL_TILE_SIZE-0.5, 0, RAIL_TILE_SIZE/2 - 0.25), // xpos
		vec3(0, 0, RAIL_TILE_SIZE/2 - 0.25)]; // xneg

	vec3[4] sideOffsetAxis = [
		vec3(-1, 0, 0), // zneg
		vec3(-1, 0, 0), // zpos
		vec3( 0, 0, 1), // xpos
		vec3( 0, 0, 1)];// xneg

	vec3[4] getSideGeometry(CubeSide side, vec3 offset, float mult) {
		return [
		vec3(cubeVerticies[cubeSideVertIndices[side][0]]) * mult + offset, // zneg
		vec3(cubeVerticies[cubeSideVertIndices[side][1]]) * mult + offset, // zpos
		vec3(cubeVerticies[cubeSideVertIndices[side][2]]) * mult + offset, // xpos
		vec3(cubeVerticies[cubeSideVertIndices[side][3]]) * mult + offset];// xneg
	}

	vec3[4] start0 = getSideGeometry(side0, sideOffsets[side0] + sideOffsetAxis[side0] + startOff, 0.5f);
	vec3[4] start1 = getSideGeometry(side0, sideOffsets[side0] - sideOffsetAxis[side0] + startOff, 0.5f);

	vec3 endOffsetAxis = sideOffsetAxis[side1];
	if (flipEndOffset) endOffsetAxis = -endOffsetAxis;
	vec3[4] end0 = getSideGeometry(side1, sideOffsets[side1] + endOffsetAxis + endOff, 0.5f);
	vec3[4] end1 = getSideGeometry(side1, sideOffsets[side1] - endOffsetAxis + endOff, 0.5f);

	const vec3[8] corners0 = [
		vec3(start0[1]), vec3(end0[2]), vec3(start0[2]), vec3(end0[1]),
		vec3(start0[0]), vec3(end0[3]), vec3(start0[3]), vec3(end0[0])];
	buffer.put4gonalPrismTris(corners0, vec3(0,0,0), color);

	const vec3[8] corners1 = [
		vec3(start1[1]), vec3(end1[2]), vec3(start1[2]), vec3(end1[1]),
		vec3(start1[0]), vec3(end1[3]), vec3(start1[3]), vec3(end1[0])];
	buffer.put4gonalPrismTris(corners1, vec3(0,0,0), color);
}
