/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module test.railroad.mesh;

import std.experimental.logger;
import std.array : Appender;
import dlib.math.vector;

import voxelman.block.utils;
import voxelman.blockentity.blockentityaccess;
import test.railroad.plugin;

void makeRailMesh(
	Appender!(ubyte[])[] output,
	BlockEntityData data,
	ubyte[3] color,
	ubyte sides,
	//ivec3 worldPos,
	ivec3 chunkPos,
	ivec3 entityPos)
{
	if (data.type == BlockEntityType.localBlockEntity && entityPos == ivec3(0,0,0))
	{
		auto sink = &output[Solidity.solid];
		for (size_t v = 0; v!=18; v+=3)
		{
			*sink ~= cast(ubyte)(railFaces[v] + chunkPos.x*POS_SCALE);
			*sink ~= cast(ubyte)(railFaces[v+1] + chunkPos.y*POS_SCALE);
			*sink ~= cast(ubyte)(railFaces[v+2] + chunkPos.z*POS_SCALE);
			*sink ~= cast(ubyte)0;
			*sink ~= cast(ubyte)(color[0]);
			*sink ~= cast(ubyte)(color[1]);
			*sink ~= cast(ubyte)(color[2]);
			*sink ~= cast(ubyte)0;
		}

		//infof("mesh %s %s %08b", chunkPos, entityPos, sides);
		//makeColoredBlockMesh(output[Solidity.solid], color,
		//	cast(ubyte)chunkPos.x,
		//	cast(ubyte)chunkPos.y,
		//	cast(ubyte)chunkPos.z,
		//	sides);
	}
}

//Volume nullBoxHandler(BlockWorldPos bwp, BlockEntityData data)

enum MESH_SIZE = RAIL_SIZE * POS_SCALE;

immutable ubyte[18] railFaces = [
	MESH_SIZE, 3, MESH_SIZE, // top
	0, 3, 0,
	0, 3, MESH_SIZE,
	MESH_SIZE, 3, MESH_SIZE,
	MESH_SIZE, 3, 0,
	0, 3, 0,];

struct Vertex
{
	this(ubyte[3] pos, ubyte[3] col) {
		position = pos;
		color = col;
	}
	union {
		struct
		{
			ubyte[3] position;
			ubyte pad1;
			ubyte[3] color;
			ubyte pad2;
		}
		ubyte[8] arrayof;
	}
}
static assert(Vertex.sizeof == 8);
