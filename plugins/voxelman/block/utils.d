/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.block.utils;

import std.experimental.logger;
import std.array : Appender;

import voxelman.math;
import voxelman.core.config;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.chunk;
import voxelman.utils.mapping;
import voxelman.core.chunkmesh;

enum Side : ubyte
{
	north	= 0,
	south	= 1,

	east	= 2,
	west	= 3,

	top		= 4,
	bottom	= 5,
}

enum SideMask : ubyte
{
	north	= 0b_00_0001,
	south	= 0b_00_0010,

	east	= 0b_00_0100,
	west	= 0b_00_1000,

	top		= 0b_01_0000,
	bottom	= 0b_10_0000,
}

enum MetadataSideMask : ushort
{
	north	= 0b_11,
	south	= 0b_11_00,

	east	= 0b_11_00_00,
	west	= 0b_11_00_00_00,

	top		= 0b_11_00_00_00_00,
	bottom	= 0b_11_00_00_00_00_00,
}

immutable Side[6] oppSide =
[Side.south,
 Side.north,
 Side.west,
 Side.east,
 Side.bottom,
 Side.top];

immutable byte[3][6] sideOffsets = [
	[ 0, 0,-1],
	[ 0, 0, 1],
	[ 1, 0, 0],
	[-1, 0, 0],
	[ 0, 1, 0],
	[ 0,-1, 0],
];

struct ChunkAndBlockAt
{
	ubyte chunk;
	ubyte blockX, blockY, blockZ;
}

// 0-5 sides, or 6 if center
ChunkAndBlockAt chunkAndBlockAt(int x, int y, int z)
{
	ubyte bx = cast(ubyte)x;
	ubyte by = cast(ubyte)y;
	ubyte bz = cast(ubyte)z;
	if(x == -1) return ChunkAndBlockAt(Side.west, CHUNK_SIZE-1, by, bz);
	else if(x == CHUNK_SIZE) return ChunkAndBlockAt(Side.east, 0, by, bz);

	if(y == -1) return ChunkAndBlockAt(Side.bottom, bx, CHUNK_SIZE-1, bz);
	else if(y == CHUNK_SIZE) return ChunkAndBlockAt(Side.top, bx, 0, bz);

	if(z == -1) return ChunkAndBlockAt(Side.north, bx, by, CHUNK_SIZE-1);
	else if(z == CHUNK_SIZE) return ChunkAndBlockAt(Side.south, bx, by, 0);

	return ChunkAndBlockAt(6, bx, by, bz);
}

Side sideFromNormal(ivec3 normal)
{
	if (normal.x == 1)
		return Side.east;
	else if (normal.x == -1)
		return Side.west;

	if (normal.y == 1)
		return Side.top;
	else if (normal.y == -1)
		return Side.bottom;

	if (normal.z == 1)
		return Side.south;
	else if (normal.z == -1)
		return Side.north;

	return Side.north;
}

void makeNullMesh(ref Appender!(MeshVertex[]), ubyte[3], ubyte, ubyte, ubyte, ubyte) {}

void makeColoredBlockMesh(ref Appender!(MeshVertex[]) output,
	ubyte[3] color, ubyte bx, ubyte by, ubyte bz, ubyte sides)
{
	import std.random;
	static immutable(float)[] shadowMultipliers = [
		0.7, 0.75, 0.6, 0.5, 0.85, 0.4,
	];

	auto index = BlockChunkIndex(bx, by, bz).index;
	auto rnd = Xorshift32(index);
	float randomTint = uniform(0.90f, 1.0f, rnd);

	float r = cast(ubyte)(color[0] * randomTint);
	float g = cast(ubyte)(color[1] * randomTint);
	float b = cast(ubyte)(color[2] * randomTint);
	ubyte[3] finalColor;

	ubyte flag = 1;
	foreach(ubyte i; 0..6)
	{
		if (sides & flag)
		{
			finalColor = [
				cast(ubyte)(shadowMultipliers[i] * r),
				cast(ubyte)(shadowMultipliers[i] * g),
				cast(ubyte)(shadowMultipliers[i] * b)];
			for (size_t v = 0; v!=18; v+=3)
			{
				output ~= MeshVertex(
					faces[18*i+v  ] + bx,
					faces[18*i+v+1] + by,
					faces[18*i+v+2] + bz,
					finalColor);
			} // for v
		} // if
		flag <<= 1;
	} // for i
}

ushort packColor(ubyte[3] c) {
	return (c[0]>>3) | (c[1]&31) << 5 | (c[2]&31) << 10;
}
ushort packColor(ubyte r, ubyte g, ubyte b) {
	return (r>>3) | (g&31) << 5 | (b&31) << 10;
}

alias BlockUpdateHandler = void delegate(BlockWorldPos bwp);
alias Meshhandler = void function(ref Appender!(MeshVertex[]) output,
	ubyte[3] color, ubyte bx, ubyte by, ubyte bz, ubyte sides);

// solidity number increases with solidity
enum Solidity : ubyte
{
	transparent,
	semiTransparent,
	solid,
}

struct BlockInfo
{
	string name;
	Meshhandler meshHandler = &makeNullMesh;
	ubyte[3] color;
	bool isVisible = true;
	Solidity solidity = Solidity.solid;
	//bool isSolid() @property const { return solidity == Solidity.solid; }
	size_t id;
}

BlockInfo entityBlock = BlockInfo("Entity", &makeColoredBlockMesh);
struct BlockInfoTable
{
	immutable(BlockInfo)[] blockInfos;
	size_t length() {return blockInfos.length; }
	BlockInfo opIndex(BlockId blockId) {
		if (blockId >= blockInfos.length)
			return entityBlock;
		return blockInfos[blockId];
	}
}

/// Returned when registering block.
/// Use this to set block properties.
struct BlockInfoSetter
{
	private Mapping!(BlockInfo)* mapping;
	private size_t blockId;
	private ref BlockInfo info() {return (*mapping)[blockId]; }

	ref BlockInfoSetter meshHandler(Meshhandler val) { info.meshHandler = val; return this; }
	ref BlockInfoSetter color(ubyte[3] color ...) { info.color = color; return this; }
	ref BlockInfoSetter colorHex(uint hex) { info.color = [(hex>>16)&0xFF,(hex>>8)&0xFF,hex&0xFF]; return this; }
	ref BlockInfoSetter isVisible(bool val) { info.isVisible = val; return this; }
	ref BlockInfoSetter solidity(Solidity val) { info.solidity = val; return this; }
}

// Chunk metadata
// 00 1 22_22_22_22_22_22
// 00 - 2 bits representing chunk's minimal solidity
// 1 - 1 bit representing if metadata is presented
// 2 - 12 bits -- solidity of each side

ushort calcChunkFullMetadata(WriteBuffer* writeBuffer, BlockInfoTable blockInfos)
{
	if (writeBuffer.isUniform) {
		ushort sideMeta = calcChunkSideMetadata(writeBuffer.getUniform!BlockId, blockInfos);
		ushort solidityBits = calcSolidityBits(writeBuffer.getUniform!BlockId, blockInfos);
		return cast(ushort) (sideMeta | solidityBits<<CHUNK_SIDE_METADATA_BITS);
	} else {
		ushort sideMeta = calcChunkSideMetadata(writeBuffer.getArray!BlockId, blockInfos);
		ushort solidityBits = calcSolidityBits(writeBuffer.getArray!BlockId, blockInfos);
		return cast(ushort) (sideMeta | solidityBits<<CHUNK_SIDE_METADATA_BITS);
	}
}

ushort calcChunkSideMetadata(WriteBuffer* writeBuffer, BlockInfoTable blockInfos)
{
	if (writeBuffer.isUniform) return calcChunkSideMetadata(writeBuffer.getUniform!BlockId, blockInfos);
	else return calcChunkSideMetadata(writeBuffer.getArray!BlockId, blockInfos);
}

ushort calcChunkSideMetadata(Layer)(Layer blockLayer, BlockInfoTable blockInfos)
	if (isSomeLayer!Layer)
{
	if (blockLayer.type == StorageType.uniform)
	{
		return calcChunkSideMetadata(blockLayer.getUniform!BlockId, blockInfos);
	}
	else if (blockLayer.type == StorageType.fullArray)
	{
		BlockId[] blocks = blockLayer.getArray!BlockId;
		return calcChunkSideMetadata(blocks, blockInfos);
	}
	else
		assert(false);
}

ubyte calcSolidityBits(Layer)(Layer blockLayer, BlockInfoTable blockInfos)
	if (isSomeLayer!Layer)
{
	if (blockLayer.type == StorageType.uniform) {
		return calcSolidityBits(blockLayer.getUniform!BlockId, blockInfos);
	} else if (blockLayer.type == StorageType.fullArray) {
		BlockId[] blocks = blockLayer.getArray!BlockId;
		return calcSolidityBits(blocks, blockInfos);
	} else assert(false);
}

ubyte calcSolidityBits(BlockId uniformBlock, BlockInfoTable blockInfos)
{
	Solidity solidity = blockInfos[uniformBlock].solidity;
	enum ubyte[3] bits = [0b001, 0b010, 0b100];
	return bits[solidity];
}

ubyte calcSolidityBits(BlockId[] blocks, BlockInfoTable blockInfos)
{
	bool[3] presentSolidities;
	foreach(i; 0..CHUNK_SIZE_CUBE) {
		Solidity solidity = blockInfos[blocks[i]].solidity;
		presentSolidities[solidity] = true;
	}
	ubyte solidityBits;
	ubyte solidityFlag = 1;
	foreach(sol; presentSolidities) {
		if (sol) solidityBits |= solidityFlag;
		solidityFlag <<= 1;
	}
	return solidityBits;
}

bool isChunkSideSolid(const ushort metadata, const Side side)
{
	return chunkSideSolidity(metadata, side) == Solidity.solid;
}

Solidity chunkSideSolidity(const ushort metadata, const Side side)
{
	if (metadata & 0b1_00_00_00_00_00_00) // if metadata is presented
		return cast(Solidity)((metadata>>(side*2)) & 0b11);
	else
		return Solidity.transparent; // otherwise non-solid
}

/// Returns true if chunk has blocks of specified solidity.
/// If metadata is invalid then chunk is assumed to have blocks of every solidity.
bool hasSolidity(const ushort metadata, Solidity solidity)
{
	ubyte solidityBits;
	if (metadata & 0b1_00_00_00_00_00_00) {// if metadata is valid
		solidityBits = (metadata>>CHUNK_SIDE_METADATA_BITS) & 0b111;
	} else {
		solidityBits = 0b111; // assume every solidity.
	}
	return (solidityBits & (1 << solidity)) > 0;
}

/// Returns true if chunk has blocks only of specified solidity.
/// If metadata is invalid then chunk is assumed to have blocks of every solidity, and returns false.
bool hasOnlySolidity(const ushort metadata, Solidity solidity)
{
	if (metadata & 0b1_00_00_00_00_00_00) {// if metadata is valid
		ubyte solidityBits = (metadata>>CHUNK_SIDE_METADATA_BITS) & 0b111;
		return solidityBits == (1 << solidity);
	} else {
		return false; // assume has every solidity.
	}
}

bool[8] singleSolidityTable = [false, true, true, false, true, false, false, false];
Solidity[8] bitsToSolidityTable = [Solidity.transparent, Solidity.transparent, Solidity.semiTransparent,
	Solidity.transparent, Solidity.solid, Solidity.transparent, Solidity.transparent, Solidity.transparent];

/// Returns true if chunk has blocks of only single solidity.
/// If returns true then solidity has solidity of all blocks.
bool hasSingleSolidity(const ushort metadata, out Solidity solidity)
{
	if (metadata & 0b1_00_00_00_00_00_00) {// if metadata is valid
		ubyte solidityBits = (metadata>>CHUNK_SIDE_METADATA_BITS) & 0b111;
		solidity = bitsToSolidityTable[solidityBits];
		return singleSolidityTable[solidityBits];
	} else {
		return false; // assume has every solidity.
	}
}

bool isMoreSolidThan(Solidity first, Solidity second)
{
	return first > second;
}

void printChunkMetadata(ushort metadata)
{
	if (metadata & 0b1_00_00_00_00_00_00) {// if metadata is valid
		char[6] sideSolidityChars;
		char[3] letters = "TMS";
		foreach(side; 0..6) {
			Solidity sideSolidity = cast(Solidity)((metadata>>(side*2)) & 0b11);
			sideSolidityChars[side] = letters[sideSolidity];
		}
		ubyte solidityBits = (metadata>>CHUNK_SIDE_METADATA_BITS) & 0b111;
		char trans = solidityBits & 1 ? 'T' : ' ';
		char semi = solidityBits & 0b10 ? 'M' : ' ';
		char solid = solidityBits & 0b100 ? 'S' : ' ';
		Solidity singleSolidity;
		bool single = hasSingleSolidity(metadata, singleSolidity);
		infof("meta [%s%s%s] (%s) {%s, %s}", trans, semi, solid, sideSolidityChars, single, singleSolidity);
	} else {
		infof("non-valid metadata");
	}
}

ushort calcChunkSideMetadata(BlockId uniformBlock, BlockInfoTable blockInfos)
{
	Solidity solidity = blockInfos[uniformBlock].solidity;
	// 13th bit == 1 when metadata is present, 12 bits = solidity of 6 chunk sides. 2 bits per side
	static immutable ushort[3] metadatas = [0b1_00_00_00_00_00_00, 0b1_01_01_01_01_01_01, 0b1_10_10_10_10_10_10];
	return metadatas[solidity];
}

enum CHUNK_SIDE_METADATA_BITS = 13;

ushort calcChunkSideMetadata(BlockId[] blocks, BlockInfoTable blockInfos)
{
	ushort flags = 0b1_00_00_00_00_00_00; // all sides are solid
	Solidity sideSolidity = Solidity.solid;
	foreach(index; 0..CHUNK_SIZE_SQR) // bottom
	{
		if (sideSolidity > blockInfos[blocks[index]].solidity)
		{
			sideSolidity -= 1;
			if (sideSolidity == Solidity.transparent)
				break;
		}
	}
	flags = cast(ushort)(flags | (sideSolidity << (Side.bottom*2)));

	sideSolidity = Solidity.solid;
	outer_north:
	foreach(y; 0..CHUNK_SIZE)
	foreach(x; 0..CHUNK_SIZE)
	{
		size_t index = y*CHUNK_SIZE_SQR | x; // north
		if (sideSolidity > blockInfos[blocks[index]].solidity)
		{
			sideSolidity -= 1;
			if (sideSolidity == Solidity.transparent)
				break outer_north;
		}
	}
	flags = cast(ushort)(flags | (sideSolidity << (Side.north*2)));

	sideSolidity = Solidity.solid;
	outer_south:
	foreach(y; 0..CHUNK_SIZE)
	foreach(x; 0..CHUNK_SIZE)
	{
		size_t index = (CHUNK_SIZE-1) * CHUNK_SIZE | y*CHUNK_SIZE_SQR | x; // south
		if (sideSolidity > blockInfos[blocks[index]].solidity)
		{
			sideSolidity -= 1;
			if (sideSolidity == Solidity.transparent)
				break outer_south;
		}
	}
	flags = cast(ushort)(flags | (sideSolidity << (Side.south*2)));

	sideSolidity = Solidity.solid;
	outer_east:
	foreach(y; 0..CHUNK_SIZE)
	foreach(z; 0..CHUNK_SIZE)
	{
		size_t index = z * CHUNK_SIZE | y*CHUNK_SIZE_SQR | (CHUNK_SIZE-1); // east
		if (sideSolidity > blockInfos[blocks[index]].solidity)
		{
			sideSolidity -= 1;
			if (sideSolidity == Solidity.transparent)
				break outer_east;
		}
	}
	flags = cast(ushort)(flags | (sideSolidity << (Side.east*2)));

	sideSolidity = Solidity.solid;
	outer_west:
	foreach(y; 0..CHUNK_SIZE)
	foreach(z; 0..CHUNK_SIZE)
	{
		size_t index = z * CHUNK_SIZE | y*CHUNK_SIZE_SQR; // west
		if (sideSolidity > blockInfos[blocks[index]].solidity)
		{
			sideSolidity -= 1;
			if (sideSolidity == Solidity.transparent)
				break outer_west;
		}
	}
	flags = cast(ushort)(flags | (sideSolidity << (Side.west*2)));

	sideSolidity = Solidity.solid;
	foreach(index; CHUNK_SIZE_CUBE-CHUNK_SIZE_SQR..CHUNK_SIZE_CUBE) // top
	{
		if (sideSolidity > blockInfos[blocks[index]].solidity)
		{
			sideSolidity -= 1;
			if (sideSolidity == Solidity.transparent)
				break;
		}
	}
	flags = cast(ushort)(flags | (sideSolidity << (Side.top*2)));

	return flags;
}


/*
void iterateSides()
{
	foreach(index; 0..CHUNK_SIZE_SQR) // bottom

	{// north
		ubyte z = 0;
		foreach(y; 0..CHUNK_SIZE)
			foreach(x; 0..CHUNK_SIZE)
				index = z * CHUNK_SIZE | y*CHUNK_SIZE_SQR | x;
	}

	{// south
		ubyte z = CHUNK_SIZE-1;
		foreach(y; 0..CHUNK_SIZE)
			foreach(x; 0..CHUNK_SIZE)
				index = z * CHUNK_SIZE | y*CHUNK_SIZE_SQR | x;
	}

	{// east
		ubyte x = CHUNK_SIZE-1;
		foreach(y; 0..CHUNK_SIZE)
			foreach(z; 0..CHUNK_SIZE)
				index = z * CHUNK_SIZE | y*CHUNK_SIZE_SQR | x;
	}

	{// west
		ubyte x = 0;
		foreach(y; 0..CHUNK_SIZE)
			foreach(z; 0..CHUNK_SIZE)
				index = z * CHUNK_SIZE | y*CHUNK_SIZE_SQR | x;
	}

	foreach(index; CHUNK_SIZE_CUBE-CHUNK_SIZE_SQR..CHUNK_SIZE_CUBE) // top
}
*/

enum POS_SCALE = ushort.max / CHUNK_SIZE;

// mesh for single block
immutable ubyte[18 * 6] faces =
[
	0, 0, 0, // triangle 1 : begin // north
	1, 1, 0,
	1, 0, 0, // triangle 1 : end
	0, 0, 0, // triangle 2 : begin
	0, 1, 0,
	1, 1, 0, // triangle 2 : end

	1, 0, 1, // south
	0, 1, 1,
	0, 0, 1,
	1, 0, 1,
	1, 1, 1,
	0, 1, 1,

	1, 0, 0, // east
	1, 1, 1,
	1, 0, 1,
	1, 0, 0,
	1, 1, 0,
	1, 1, 1,

	0, 0, 1, // west
	0, 1, 0,
	0, 0, 0,
	0, 0, 1,
	0, 1, 1,
	0, 1, 0,

	1, 1, 1, // top
	0, 1, 0,
	0, 1, 1,
	1, 1, 1,
	1, 1, 0,
	0, 1, 0,

	0, 0, 1, // bottom
	1, 0, 0,
	1, 0, 1,
	0, 0, 1,
	0, 0, 0,
	1, 0, 0,
];
