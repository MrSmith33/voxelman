/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.block.shape;

import voxelman.log;
import voxelman.core.config;

/*
block shapes:

empty		empty x6
full		full x6
half		full + empty + half x4
stairs		stairs x2 + half x2 + fullx2
slope		slope x2 + full x2 + empty x2
corner		slope x3 + empty x3
inner		slope x3 + full x3
pyramid		slope x2 + full x1 + empty x3

side masks:

empty
full
half
slope
stairs

corners: (1 corner has mesh, 0 has no mesh)

empty		0 x8
full		1 x8
half		1 x4 + 0 x4
stairs		1 x6 + 0 x2
slope		1 x6 + 0 x2
corner		1 x4 + 0 x4
inner		1 x7 + 0 x1
pyramid		1 x5 + 0 x5

has middle piece

empty		no
full		no
half		yes
stairs		yes
slope		yes
corner		yes
inner		yes
pyramid		yes
*/

// index is side shape
// value is
ubyte[] blockSideCorners = [
	// 3210 corners
	0b_0000, // empty
	0b_1111, // full
	0b_0110, // half
	0b_0111, // slope
	0b_0111, // stairs
];

enum NUM_SIDE_MASKS = ShapeSideMask.max + 1;

enum ShapeSideMask : ubyte
{
	empty,
	water,
	full,
	half,
	slope0, // top-left
	slope1, // bot-left
	slope2, // bot-right
	slope3, // top-right
	stairs,
}

struct ShapeSide
{
	ShapeSideMask mask;
	ubyte rotation;
}

struct BlockShape
{
	ShapeSideMask[6] sideMasks;
	ubyte corners; // bits are corners
	bool hasGeometry;
	bool hasInternalGeometry;
}

import std.range : repeat, take;
import std.array : array;
const ShapeSideMask[6] fullShapeSides = ShapeSideMask.full.repeat.take(6).array;
const ShapeSideMask[6] waterShapeSides = ShapeSideMask.water.repeat.take(6).array;
const ShapeSideMask[6] emptyShapeSides = ShapeSideMask.empty.repeat.take(6).array;

const BlockShape unknownShape = BlockShape(fullShapeSides, 0b_0000_0000, false, false);
const BlockShape fullShape = BlockShape(fullShapeSides, 0b_1111_1111, true, false);
const BlockShape waterShape = BlockShape(waterShapeSides, 0b_1111_1111, false, false);
const BlockShape emptyShape = BlockShape(emptyShapeSides, 0b_0000_0000, false, false);

BlockShape slopeShapeFromMeta(BlockMetadata metadata)
{
	return metaToShapeTable[metadata];
}

private alias SSM = ShapeSideMask;
BlockShape[12] metaToShapeTable = [
	//zneg        zpos        xpos        xneg        ypos       yneg
	{[SSM.full,   SSM.empty,  SSM.slope2, SSM.slope1, SSM.empty, SSM.full], 0b_0011_1111, true, true}, // 0, yneg full
	{[SSM.slope1, SSM.slope2, SSM.full,   SSM.empty,  SSM.empty, SSM.full], 0b_1010_1111, true, true}, // 1
	{[SSM.empty,  SSM.full,   SSM.slope1, SSM.slope2, SSM.empty, SSM.full], 0b_1100_1111, true, true}, // 2
	{[SSM.slope2, SSM.slope1, SSM.empty,  SSM.full,   SSM.empty, SSM.full], 0b_0101_1111, true, true}, // 3

	{[SSM.full, SSM.empty, SSM.slope0, SSM.slope0, SSM.empty, SSM.full], 0b_0011_1111, true, true}, // TODO 0, vertiacl sides full
	{[SSM.full, SSM.empty, SSM.slope0, SSM.slope0, SSM.empty, SSM.full], 0b_0011_1111, true, true}, // TODO 1
	{[SSM.full, SSM.empty, SSM.slope0, SSM.slope0, SSM.empty, SSM.full], 0b_0011_1111, true, true}, // TODO 2
	{[SSM.full, SSM.empty, SSM.slope0, SSM.slope0, SSM.empty, SSM.full], 0b_0011_1111, true, true}, // TODO 3

	{[SSM.full, SSM.empty, SSM.slope0, SSM.slope0, SSM.empty, SSM.full], 0b_0011_1111, true, true}, // TODO 0, ypos full
	{[SSM.full, SSM.empty, SSM.slope0, SSM.slope0, SSM.empty, SSM.full], 0b_0011_1111, true, true}, // TODO 1
	{[SSM.full, SSM.empty, SSM.slope0, SSM.slope0, SSM.empty, SSM.full], 0b_0011_1111, true, true}, // TODO 2
	{[SSM.full, SSM.empty, SSM.slope0, SSM.slope0, SSM.empty, SSM.full], 0b_0011_1111, true, true}, // TODO 3
];

/*
struct SideIntersectionTable
{
	ubyte[] table;
	size_t numTypes;

	/// Returns true if current shape side is visible
	pragma(inline, true)
	bool get(const ShapeSideMask current, const ShapeSideMask other)
	{
		size_t index = current * numTypes + other;
		return (table[index>>3] & (1 << (index & 0b111))) != 0;
	}

	void set(const ShapeSideMask current, const ShapeSideMask other)
	{
		size_t index = current * numTypes + other;
		table[index>>3] |= (1 << (index & 0b111));
	}

	void reset(const ShapeSideMask current, const ShapeSideMask other)
	{
		size_t index = current * numTypes + other;
		table[index>>3] &= ~(1 << (index & 0b111));
	}
}

SideIntersectionTable sideIntersectionTable(size_t numTypes)
{
	size_t tableBits = numTypes * numTypes;
	size_t tableBytes = tableBits/8 + 1;
	return SideIntersectionTable(new ubyte[tableBytes], numTypes);
}*/

struct SideIntersectionTable
{
	bool[] table;
	size_t numTypes;

	/// Returns true if current shape side is visible
	pragma(inline, true)
	bool get(const ShapeSideMask current, const ShapeSideMask other)
	{
		size_t index = current * numTypes + other;
		return table[index];
	}

	void set(const ShapeSideMask current, const ShapeSideMask other)
	{
		size_t index = current * numTypes + other;
		table[index] = true;
	}

	void reset(const ShapeSideMask current, const ShapeSideMask other)
	{
		size_t index = current * numTypes + other;
		table[index] = false;
	}
}

SideIntersectionTable sideIntersectionTable(size_t numTypes)
{
	size_t tableBits = numTypes * numTypes;
	//size_t tableBytes = tableBits/8 + 1;
	return SideIntersectionTable(new bool[tableBits], numTypes);
}
