/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module test.railroad.mesh;

import std.experimental.logger;
import std.array : Appender;
import dlib.math.vector;

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
		putRailMesh(output[Solidity.solid], chunkPos, RailData(data));
	}
}

void putRailMesh(ref Appender!(MeshVertex[]) sink, ivec3 chunkPos, RailData data)
{
	auto chunkPosF = vec3(chunkPos);
	foreach(v; railMesh_1)
	{
		sink.put(MeshVertex((vec3(v.position) + chunkPosF).arrayof, v.color));
	}
}

__gshared MeshVertex[] railMesh_1;
__gshared MeshVertex[] railMesh_2;
__gshared MeshVertex[] railMesh_3;
