/**
Copyright: Copyright (c) 2016-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module railroad.rail.utils;

import voxelman.math;
import voxelman.geometry;
import voxelman.world.block;
import voxelman.world.blockentity.blockentitydata;
import voxelman.world.blockentity.blockentityaccess;
import voxelman.world.blockentity.utils;
import voxelman.world.storage;
import voxelman.world.mesh.utils : FaceSide, oppFaceSides;

enum RAIL_TILE_SIZE = 8;
immutable ivec3 railSizeVector = ivec3(RAIL_TILE_SIZE, 1, RAIL_TILE_SIZE);
immutable ivec4 railPickOffset = ivec4(RAIL_TILE_SIZE/2, 0, RAIL_TILE_SIZE/2, 0);

ivec3 railTilePos(ivec3 bwp) {
	return ivec3(floor(cast(float)bwp.x / RAIL_TILE_SIZE) * RAIL_TILE_SIZE,
		bwp.y,
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
		ushort blockIndex = blockEntityIndexFromBlockId(blockId);
		BlockEntityData entity = entityAccess.getBlockEntity(railPos.chunkPos, blockIndex);

		if (entity.id == railEntityId)
			return RailData(entity);
	}
	return RailData();
}

enum RailEditOp
{
	add,
	remove
}

struct RailPos {
	this(svec4 vec) {
		vector = vec;
	}
	this(BlockWorldPos bwp)
	{
		vector = svec4(
			floor(cast(float)bwp.x / RAIL_TILE_SIZE),
			cast(float)bwp.y,
			floor(cast(float)bwp.z / RAIL_TILE_SIZE),
			bwp.w);
	}
	ChunkWorldPos chunkPos() const {
		return ChunkWorldPos(toBlockWorldPos());
	}
	BlockWorldPos toBlockWorldPos() const {
		return BlockWorldPos(
			vector.x * RAIL_TILE_SIZE,
			vector.y,
			vector.z * RAIL_TILE_SIZE,
			vector.w);
	}
	WorldBox toBlockBox() const
	{
		return WorldBox(toBlockWorldPos().xyz, railSizeVector, vector.w);
	}
	BlockWorldPos deletePos() const
	{
		auto bwp = toBlockWorldPos;
		bwp.vector += railPickOffset;
		return bwp;
	}
	svec4 vector;
	alias vector this;

	ulong asUlong() const @property
	{
		ulong res = cast(ulong)vector.w<<48 |
				cast(ulong)(cast(ushort)vector.z)<<32 |
				cast(ulong)(cast(ushort)vector.y)<<16 |
				cast(ulong)(cast(ushort)vector.x);
		return res;
	}

	RailPos posInDirection(FaceSide direction)
	{
		byte[3] offset = sideToOffset[direction];
		return RailPos(svec4(
			vector.x+offset[0],
			vector.y+offset[1],
			vector.z+offset[2],
			vector.w));
	}
}

immutable byte[3][4] sideToOffset = [
	[ 0, 0,-1],
	[-1, 0, 0],
	[ 0, 0, 1],
	[ 1, 0, 0]];

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

	bool isSlope() const {
		return (data & SLOPE_RAIL_BIT) != 0;
	}

	bool hasSingleSegment() const {
		if ((data & SLOPE_RAIL_BIT) != 0)
		{
			return 1;
		}
		else
		{
			import core.bitop : popcnt;
			return popcnt(data) == 1;
		}
	}

	bool empty() const {
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

	void removeRail(RailData newRail)
	{
		if (data == newRail.data) // slope or multiple same rails
		{
			data = 0;
		}
		else
		{
			data &= ~cast(int)(newRail.data);
		}
	}

	void editRail(RailData railData, RailEditOp editOp)
	{
		final switch(editOp)
		{
			case RailEditOp.add: addRail(railData); break; // combine rails
			case RailEditOp.remove: removeRail(railData); break; // remove rails
		}
	}

	SegmentRange getSegments() const
	{
		return SegmentRange(data);
	}

	// returns segments that connect to the side
	SegmentBuffer getSegmentsFromSide(FaceSide side)
	{
		SegmentBuffer result;
		foreach(RailSegment segment; getSegments)
		{
			if (segmentInfos[segment].sideConnections[side])
				result.put(segment);
		}
		return result;
	}

	// returns segments that connect to the side
	// and create smooth curve with adjacent segment
	// adjacent segment is guaranteed to be connected to the side
	SegmentBuffer getSegmentsFromSideSmooth(FaceSide side, RailSegment adjacent)
	{
		assert(segmentInfos[adjacent].sideConnections[oppFaceSides[side]],
			"Adjacent segment must be connected to the side");
		SegmentBuffer result;
		foreach(RailSegment segment; getSegments)
		{
			if (segmentInfos[segment].sideConnections[side])
			{
				// TODO
				result.put(segment);
			}
		}
		return result;
	}

	Solidity bottomSolidity(ivec3 blockTilePos) const
	{
		foreach(segment; getSegments)
		{
			if (isSegmentSolid(segment, blockTilePos))
				return Solidity.solid;
		}

		return Solidity.transparent;
	}

	WorldBox boundingBox(RailPos railPos) const
	{
		return boundingBox(railPos.toBlockWorldPos());
	}

	WorldBox boundingBox(BlockWorldPos bwp) const
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

import voxelman.container.fixedbuffer;
alias SegmentBuffer = FixedBuffer!(RailSegment, 3);

struct SegmentRange
{
	this(ubyte _data)
	{
		data = _data;
	}

	private ubyte data;

	int opApply(scope int delegate(size_t, RailSegment) del)
	{
		size_t index;
		int proxyDel(RailSegment segment) { return del(index++, segment); }
		return opApply(&proxyDel);
	}

	int opApply(scope int delegate(RailSegment) del)
	{
		if ((data & SLOPE_RAIL_BIT) != 0)
		{
			ubyte segment = cast(ubyte)(data - SLOPE_RAIL_BIT + RailSegment.znegUp);
			if (auto ret = del(cast(RailSegment)segment))
				return ret;
		}
		else if (data != 0)
		{
			import core.bitop : bsf;

			ubyte segment = cast(ubyte)bsf(data);
			ubyte flag = cast(ubyte)(1 << segment);

			while(segment <= RailSegment.xposZneg)
			{
				if (flag & data)
					if (auto ret = del(cast(RailSegment)segment))
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

enum SEGMENT_LENGTH_STRAIGHT = 8;
enum SEGMENT_LENGTH_DIAGONAL = 4*SQRT_2;
enum SEGMENT_LENGTH_SLOPE = sqrt(8.0*8.0 + 1*1);

float[] segmentLengths = [
	SEGMENT_LENGTH_STRAIGHT,
	SEGMENT_LENGTH_STRAIGHT,

	SEGMENT_LENGTH_DIAGONAL,
	SEGMENT_LENGTH_DIAGONAL,
	SEGMENT_LENGTH_DIAGONAL,
	SEGMENT_LENGTH_DIAGONAL,

	SEGMENT_LENGTH_SLOPE,
	SEGMENT_LENGTH_SLOPE,
	SEGMENT_LENGTH_SLOPE,
	SEGMENT_LENGTH_SLOPE,
];

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

// slopeUpToSide[data & 0b11]
CubeSide[4] slopeUpToSide = [
	CubeSide.zneg,
	CubeSide.xneg,
	CubeSide.zpos,
	CubeSide.xpos];

bool isSlopeUpSideBlock(RailData railData, ivec3 entityPos, out CubeSide sideToMesh)
{
	sideToMesh = slopeUpToSide[railData.data & 0b11];
	switch(sideToMesh)
	{
		case CubeSide.zneg: return entityPos.z == 0;
		case CubeSide.xneg: return entityPos.x == 0;
		case CubeSide.zpos: return entityPos.z == Z_RAIL_SIZE.z - 1;
		case CubeSide.xpos: return entityPos.x == X_RAIL_SIZE.x - 1;
		default: assert(false);
	}
}

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

bool isSegmentSolid(RailSegment segment, ivec3 blockTilePos)
{
	import core.bitop : bt;
	auto bitmapId = bt(cast(size_t*)&railSegmentBottomSolidityIndex, segment);
	ubyte rotation = railSegmentMeshRotation[segment];
	// Size needs to be less by 1 for correct shift
	ivec3 rotatedPos = rotatePointShiftOriginCW!ivec3(blockTilePos, ivec3(7,0,7), rotation);
	// Invert bit order (63 - bit num) add bitnum id offset of 64
	auto tileIndex = 63 - (rotatedPos.x + rotatedPos.z * RAIL_TILE_SIZE) + 64 * bitmapId;
	return !!bt(cast(size_t*)&railBottomSolidityBitmaps, tileIndex);
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

// Rail tile can have a number of these. I.e. straight, diagonal rails are segments.
struct SegmentInfo
{
	// Sides of rail tile that this segment connects to
	// 0 zneg, 1 xneg, 2 zpos, 3 xpos
	FaceSide[2] sides;
	bool[4] sideConnections;
	// 0 - first connection (item at sides[0]), 1 - second connection (item at sides[1]). Non-connected sides also use 0.
	// Only indicies stated in 'sides' are relevant
	ubyte[4] sideIndicies;
}

// relative to 8x8 tile
vec3[] railTileConnectionPoints = [
	vec3(4, 0.5, 0),
	vec3(0, 0.5, 4),
	vec3(4, 0.5, 8),
	vec3(8, 0.5, 4),
];

SegmentInfo[10] segmentInfos = [
	{cast(FaceSide[2])[0, 2], [true,  false, true,  false], [0, 0, 1, 0]}, // zneg,
	{cast(FaceSide[2])[1, 3], [false, true,  false, true ], [0, 0, 0, 1]}, // xpos,

	{cast(FaceSide[2])[1, 0], [true,  true,  false, false], [1, 0, 0, 0]}, // xnegZneg,
	{cast(FaceSide[2])[1, 2], [false, true,  true,  false], [0, 0, 1, 0]}, // xnegZpos,
	{cast(FaceSide[2])[3, 2], [false, false, true,  true ], [0, 0, 1, 0]}, // xposZpos,
	{cast(FaceSide[2])[3, 0], [true,  false, false, true ], [1, 0, 0, 0]}, // xposZneg,

	{cast(FaceSide[2])[0, 2], [true,  false, false, false], [0, 0, 0, 0]}, // znegUp,
	{cast(FaceSide[2])[1, 3], [false, true,  false, false], [0, 0, 0, 0]}, // xnegUp,
	{cast(FaceSide[2])[2, 0], [false, false, true,  false], [0, 0, 0, 0]}, // zposUp,
	{cast(FaceSide[2])[3, 1], [false, false, false, true ], [0, 0, 0, 0]}, // xposUp,
];

struct SmoothConnections
{
	ushort data;
	bool isSmoothWith(RailSegment segment)
	{
		return true; // TODO
	}
}

// Table which gives info on valid transitions between segments for wagons
SmoothConnections[] segmentSmoothConnectionTbl = [
];


import voxelman.graphics;

void railDebugHandler(ref BlockEntityDebugContext context)
{
	drawSolidityDebug(context.graphics.debugBatch, RailData(context.data), context.bwp);
}

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

// Diagonal rail utils

enum RailOrientation
{
	x,
	xzOppSign, // xneg-zpos, xpos-zneg
	z,
	xzSameSign, //xneg-zneg, xpos-zpos
}

enum DiagonalRailSide
{
	zpos,
	zneg
}

ivec2 addDiagonalManhattan(ivec2 origin, int distance, RailOrientation orientation, DiagonalRailSide side)
{
	bool topSide = side == DiagonalRailSide.zneg;
	int odd = distance % 2 != 0;

	switch(orientation)
	{
		case RailOrientation.xzSameSign:
			ivec2 oddIncrement = topSide ? ivec2(0, -1) : ivec2(1, 0);
			return origin + ivec2(1, -1) * cast(int)floor(distance/2.0f) + oddIncrement * odd;

		case RailOrientation.xzOppSign:
			ivec2 oddIncrement = topSide ? ivec2(1, 0) : ivec2(0,  1);
			return origin + ivec2(1,  1) * cast(int)floor(distance/2.0f) + oddIncrement * odd;

		default: assert(false);
	}
}

