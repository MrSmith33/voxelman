/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module test.railroad.utils;

import voxelman.geometry.box;
import voxelman.utils.math;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.worldbox;
import voxelman.blockentity.blockentitydata;

enum RAIL_TILE_SIZE = 8;
ivec3 railSizeVector = vec3(RAIL_TILE_SIZE, 1, RAIL_TILE_SIZE);

ivec3 railTilePos(BlockWorldPos bwp) {
	return ivec3(floor(cast(float)bwp.x / RAIL_TILE_SIZE) * RAIL_TILE_SIZE,
		cast(float)bwp.y,
		floor(cast(float)bwp.z / RAIL_TILE_SIZE) * RAIL_TILE_SIZE);
}

struct RailPos {
	this(BlockWorldPos bwp)
	{
		vector = svec4(
			floor(cast(float)bwp.x / RAIL_TILE_SIZE),
			cast(float)bwp.y,
			floor(cast(float)bwp.z / RAIL_TILE_SIZE),
			bwp.w);
	}
	ChunkWorldPos chunkPos() {
		return ChunkWorldPos(toBlockWorldPos());
	}
	BlockWorldPos toBlockWorldPos() {
		return BlockWorldPos(
			vector.x * RAIL_TILE_SIZE,
			vector.y,
			vector.z * RAIL_TILE_SIZE,
			vector.w);
	}
	WorldBox toBlockBox()
	{
		return WorldBox(toBlockWorldPos().xyz, railSizeVector, vector.w);
	}
	svec4 vector;
}

struct RailData
{
	ubyte data;

	this(ubyte eData) {
		data = eData;
	}

	this(BlockEntityData beData) {
		data = cast(ubyte)(beData.entityData);
	}

	bool isSlope() {
		return (data & SLOPE_RAIL_BIT) != 0;
	}

	WorldBox boundingBox(BlockWorldPos bwp)
	{
		if (isSlope)
		{
			auto segment = data - SLOPE_RAIL_BIT + RailSegment.northUp;
			ivec3 tilePos = railTilePos(bwp);
			ivec3 railPos = tilePos + railSegmentOffsets[segment];
			ivec3 railSize = railSegmentSizes[segment];
			return WorldBox(railPos, railSize, cast(ushort)(bwp.w));
		}
		else
		{
			ivec3 tilePos = railTilePos(bwp);

			Box commonBox;
			ubyte flag = 1;
			foreach(segment; 0..6)
			{
				if (flag & data)
				{
					ivec3 segmentPos = railSegmentOffsets[segment];
					ivec3 segmentSize = railSegmentSizes[segment];
					Box box = Box(segmentPos, segmentSize);
					if (commonBox.empty)
						commonBox = box;
					else
						commonBox = calcCommonBox(commonBox, box);
				}

				flag <<= 1;
			}
			commonBox.position += tilePos;

			return WorldBox(commonBox, cast(ushort)(bwp.w));
		}
	}
}

enum RailSegment
{
	north, //zNeg
	east, //xPos
	eastNorth, //xPos zNeg
	westNorth, //xNeg zNeg
	westSouth, //xNeg zPos
	eastSouth, //xPos zPos

	northUp,
	southUp,
	eastUp,
	westUp,

	//northDown = southUp,
	//southDown = northUp,
	//eastDown = westUp,
	//westDown = eastUp,
}

enum SLOPE_RAIL_BIT = 0b0100_0000;
ubyte[] railSegmentData =
[
	1,
	2,
	4,
	8,
	16,
	32,
	SLOPE_RAIL_BIT + 0,
	SLOPE_RAIL_BIT + 1,
	SLOPE_RAIL_BIT + 2,
	SLOPE_RAIL_BIT + 3];

enum NORTH_RAIL_SIZE = ivec3(4, 1, 8);
enum EAST_RAIL_SIZE = ivec3(8, 1, 4);
enum DIAGONAL_RAIL_SIZE = ivec3(6, 1, 6);

// [x, z]
ivec3[] railSegmentSizes = [
	NORTH_RAIL_SIZE, // north
	EAST_RAIL_SIZE, // east
	DIAGONAL_RAIL_SIZE, // eastNorth
	DIAGONAL_RAIL_SIZE, // westNorth
	DIAGONAL_RAIL_SIZE, // westSouth
	DIAGONAL_RAIL_SIZE, // eastSouth

	NORTH_RAIL_SIZE, // northUp
	NORTH_RAIL_SIZE, // southUp
	EAST_RAIL_SIZE, // eastUp
	EAST_RAIL_SIZE, // westUp
];

enum NORTH_RAIL_OFFSET = ivec3(2, 0, 0);
enum EAST_RAIL_OFFSET = ivec3(0, 0, 2);

// [x, z]
ivec3[] railSegmentOffsets = [
	NORTH_RAIL_OFFSET, // north
	EAST_RAIL_OFFSET, // east
	ivec3(2, 0, 0), // eastNorth
	ivec3(0, 0, 0), // westNorth
	ivec3(0, 0, 2), // westSouth
	ivec3(0, 0, 2), // eastSouth

	NORTH_RAIL_OFFSET, // northUp
	NORTH_RAIL_OFFSET, // southUp
	EAST_RAIL_OFFSET, // eastUp
	EAST_RAIL_OFFSET, // westUp
];
