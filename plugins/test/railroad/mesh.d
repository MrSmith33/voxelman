/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module test.railroad.mesh;

import std.experimental.logger;
import std.array : Appender;
import std.range;
import std.conv : to;
import voxelman.math;

import voxelman.geometry.utils;

import voxelman.core.chunkmesh;
import voxelman.block.utils;
import voxelman.blockentity.blockentityaccess;
import voxelman.blockentity.blockentitydata;

import test.railroad.utils;

void makeRailMesh(
	Appender!(MeshVertex[])[] output,
	BlockEntityData data,
	ubyte[3] color,
	ubyte sides,
	//ivec3 worldPos,
	ivec3 chunkPos,
	ivec3 entityPos)
{
	if (data.type == BlockEntityType.localBlockEntity && entityPos == ivec3(0,0,0))
	{
		putRailMesh!MeshVertex(output[Solidity.solid], chunkPos, RailData(data));
	}
}

void putRailMesh(Vert, Sink)(ref Sink sink, ivec3 chunkPos, RailData data)
{
	alias Pos = typeof(Vert.position);
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
		foreach(v; mesh)
		{
			vec3 pos = rotator(vec3(v.position), meshSize) + offset;
			sink.put(Vert(Pos(pos), v.color));
		}
	}
}

__gshared MeshVertex[][3] railMeshes;
ivec3[3] meshSizes = [
	ivec3(4, 1, 8),
	ivec3(6, 1, 6),
	ivec3(4, 1, 8)];
