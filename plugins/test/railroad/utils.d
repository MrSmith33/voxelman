/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module test.railroad.utils;

import voxelman.math;
import voxelman.geometry.box;
import voxelman.geometry.utils;
import voxelman.world.block;
import voxelman.blockentity.blockentitydata;
import voxelman.blockentity.blockentityaccess;
import voxelman.blockentity.utils;
import voxelman.world.storage;

enum RAIL_TILE_SIZE = 8;
immutable ivec3 railSizeVector = ivec3(RAIL_TILE_SIZE, 1, RAIL_TILE_SIZE);
immutable ivec4 railPickOffset = ivec4(RAIL_TILE_SIZE/2, 0, RAIL_TILE_SIZE/2, 0);

ivec3 railTilePos(ivec3 bwp) {
	return ivec3(floor(cast(float)bwp.x / RAIL_TILE_SIZE) * RAIL_TILE_SIZE,
		cast(float)bwp.y,
		floor(cast(float)bwp.z / RAIL_TILE_SIZE) * RAIL_TILE_SIZE);
}

ivec3 calcBlockTilePos(ivec3 bwp)
{
	ivec3 tilePos = railTilePos(bwp);
	return bwp - tilePos;
}

RailData getRailAt(RailPos railPos, ushort railEntityId,
	WorldAccess worldAccess, BlockEntityAccess entityAccess)
{
	auto bwp = railPos.toBlockWorldPos;
	bwp.vector += railPickOffset;
	auto blockId = worldAccess.getBlock(bwp);

	if (isBlockEntity(blockId))
	{
		ushort blockIndex = blockIndexFromBlockId(blockId);
		BlockEntityData entity = entityAccess.getBlockEntity(railPos.chunkPos, blockIndex);

		if (entity.id == railEntityId)
			return RailData(entity);
	}
	return RailData();
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
	BlockWorldPos deletePos()
	{
		auto bwp = toBlockWorldPos;
		bwp.vector += railPickOffset;
		return bwp;
	}
	svec4 vector;
}

struct RailData
{
	ubyte data;

	this(ubyte eData) {
		data = eData;
	}

	this(RailSegment segment) {
		data = railSegmentData[segment];
	}

	this(BlockEntityData beData) {
		data = cast(ubyte)(beData.entityData);
	}

	bool isSlope() {
		return (data & SLOPE_RAIL_BIT) != 0;
	}

	bool empty() {
		return data == 0;
	}

	void addRail(RailData newRail)
	{
		if (newRail.isSlope || isSlope)
		{
			data = newRail.data;
		}
		else
		{
			data |= newRail.data;
		}
	}

	SegmentRange getSegments()
	{
		return SegmentRange(data);
	}

	Solidity bottomSolidity(ivec3 blockTilePos)
	{
		foreach(segment; getSegments)
		{
			if (isSegmentSolid(segment, blockTilePos))
				return Solidity.solid;
		}

		return Solidity.transparent;
	}

	WorldBox boundingBox(RailPos railPos)
	{
		return boundingBox(railPos.toBlockWorldPos());
	}

	WorldBox boundingBox(BlockWorldPos bwp)
	{
		if (isSlope)
		{
			auto segment = data - SLOPE_RAIL_BIT + RailSegment.znegUp;
			ivec3 tilePos = railTilePos(bwp.xyz);
			ivec3 railPos = tilePos + railSegmentOffsets[segment];
			ivec3 railSize = railSegmentSizes[segment];
			return WorldBox(railPos, railSize, cast(ushort)(bwp.w));
		}
		else
		{
			ivec3 tilePos = railTilePos(bwp.xyz);

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

struct SegmentRange
{
	this(ubyte _data)
	{
		data = _data;
		assert(data != 0);
	}

	private ubyte data;

	int opApply(scope int delegate(ubyte) del)
	{
		if ((data & SLOPE_RAIL_BIT) != 0)
		{
			ubyte segment = cast(ubyte)(data - SLOPE_RAIL_BIT + RailSegment.znegUp);
			if (auto ret = del(segment))
				return ret;
		}
		else
		{
			import core.bitop : bsf;

			ubyte segment = cast(ubyte)bsf(data);
			ubyte flag = cast(ubyte)(1 << segment);

			while(segment <= RailSegment.xposZneg)
			{
				if (flag & data)
					if (auto ret = del(segment))
						return ret;
				flag <<= 1;
				++segment;
			}
		}
		return 0;
	}
}

enum RailSegment
{
	zneg,
	xpos,

	xnegZneg,
	xnegZpos,
	xposZpos,
	xposZneg,

	znegUp,
	xnegUp,
	zposUp,
	xposUp,

	//znegDown = zposUp,
	//zposDown = znegUp,
	//xposDown = xnegUp,
	//xnegDown = xposUp,
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

enum Z_RAIL_SIZE = ivec3(4, 1, 8);
enum X_RAIL_SIZE = ivec3(8, 1, 4);
enum DIAGONAL_RAIL_SIZE = ivec3(6, 1, 6);

// [x, z]
ivec3[] railSegmentSizes = [
	Z_RAIL_SIZE, // zneg
	X_RAIL_SIZE, // xpos

	DIAGONAL_RAIL_SIZE, // xnegZneg
	DIAGONAL_RAIL_SIZE, // xnegZpos
	DIAGONAL_RAIL_SIZE, // xposZpos
	DIAGONAL_RAIL_SIZE, // xposZneg

	Z_RAIL_SIZE, // znegUp
	X_RAIL_SIZE, // xnegUp
	Z_RAIL_SIZE, // zposUp
	X_RAIL_SIZE, // xposUp
];

enum Z_RAIL_OFFSET = ivec3(2, 0, 0);
enum X_RAIL_OFFSET = ivec3(0, 0, 2);

// [x, z]
ivec3[] railSegmentOffsets = [
	Z_RAIL_OFFSET, // zneg
	X_RAIL_OFFSET, // xpos

	ivec3(0, 0, 0), // xnegZneg
	ivec3(0, 0, 2), // xnegZpos
	ivec3(2, 0, 2), // xposZpos
	ivec3(2, 0, 0), // xposZneg

	Z_RAIL_OFFSET, // znegUp
	X_RAIL_OFFSET, // xnegUp
	Z_RAIL_OFFSET, // zposUp
	X_RAIL_OFFSET, // xposUp
];


ubyte[] railSegmentMeshId = [0, 0, 1, 1, 1, 1, 2, 2, 2, 2];
ubyte[] railSegmentMeshRotation = [0, 1, 0, 1, 2, 3, 0, 1, 2, 3];

void rotateSegment(ref RailSegment segment)
{
	++segment;
	if (segment > RailSegment.max)
		segment = RailSegment.min;
}

bool isSegmentSolid(ubyte segment, ivec3 blockTilePos)
{
	import core.bitop : bt;
	auto bitmapId = bt(cast(size_t*)&railSegmentBottomSolidityIndex, segment);
	alias Bitmap = size_t[ulong.sizeof / size_t.sizeof];
	Bitmap bitmap = *cast(Bitmap*)&railBottomSolidityBitmaps[bitmapId];
	ubyte rotation = railSegmentMeshRotation[segment];
	// Size needs to me less by 1 for correct shift
	ivec3 rotatedPos = rotatePointShiftOriginCW!ivec3(blockTilePos, ivec3(7,0,7), rotation);
	// Invert bit order (63 - bit num)
	auto tileIndex = 63 - (rotatedPos.x + rotatedPos.z * RAIL_TILE_SIZE);
	return !!bt(bitmap.ptr, tileIndex);
}

ushort railSegmentBottomSolidityIndex = 0b0000_1111_00;

ulong[2] railBottomSolidityBitmaps = [
mixin("0b"~ // !bit order is right to left!
"00111100"~
"00111100"~
"00111100"~
"00111100"~
"00111100"~
"00111100"~
"00111100"~
"00111100"),
mixin("0b"~
"00111000"~
"01110000"~
"11100000"~
"11000000"~
"10000000"~
"00000000"~
"00000000"~
"00000000")];

import voxelman.graphics;
void drawSolidityDebug(ref Batch b, RailData data, BlockWorldPos bwp)
{
	ivec3 tilePos = railTilePos(bwp.xyz);
	ivec3 blockTilePos = bwp.xyz - tilePos;

	foreach(segment; data.getSegments)
	{
		foreach(z; 0..RAIL_TILE_SIZE)
		foreach(x; 0..RAIL_TILE_SIZE)
		{
			auto blockPos = ivec3(x, 0, z);
			if (isSegmentSolid(segment, blockPos))
			{
				auto renderPos = tilePos + ivec3(x, segment, z);
				enum cursorOffset = vec3(0.01, 0.01, 0.01);
				b.putCube(vec3(renderPos) - cursorOffset + vec3(0.25,0.25,0.25),
					vec3(0.5,0.5,0.5) + cursorOffset, Colors.black, true);
			}
		}
	}
}
