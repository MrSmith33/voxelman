/**
Copyright: Copyright (c) 2013-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.block.blocklayermetadata;

import voxelman.log;
import voxelman.geometry.cube;
import voxelman.core.config;
import voxelman.world.block;
import voxelman.world.storage;

// Chunk metadata
// 00 1 22_22_22_22_22_22
// 00 - 2 bits representing chunk's minimal solidity
// 1 - 1 bit representing if metadata is presented
// 2 - 12 bits -- solidity of each side

enum MetadataSideMask : ushort
{
	zneg = 0b_11,
	zpos = 0b_11_00,

	xpos = 0b_11_00_00,
	xneg = 0b_11_00_00_00,

	ypos = 0b_11_00_00_00_00,
	yneg = 0b_11_00_00_00_00_00,
}

// Works only with uncompressed data.
ushort calcChunkFullMetadata(Layer)(const ref Layer blockLayer, BlockInfoTable blockInfos)
{
	if (blockLayer.type == StorageType.uniform) {
		return calcChunkFullMetadata(blockLayer.getUniform!BlockId, blockInfos);
	} else if (blockLayer.type == StorageType.fullArray) {
		return calcChunkFullMetadata(blockLayer.getArray!BlockId, blockInfos);
	} else assert(false);
}

ushort calcChunkFullMetadata(BlockId[] blocks, BlockInfoTable blockInfos)
{
	ushort sideMeta = calcChunkSideMetadata(blocks, blockInfos);
	ushort solidityBits = calcSolidityBits(blocks, blockInfos);
	return cast(ushort) (sideMeta | solidityBits<<CHUNK_SIDE_METADATA_BITS);
}

ushort calcChunkFullMetadata(BlockId uniformBlock, BlockInfoTable blockInfos)
{
	ushort sideMeta = calcChunkSideMetadata(uniformBlock, blockInfos);
	ushort solidityBits = calcSolidityBits(uniformBlock, blockInfos);
	return cast(ushort) (sideMeta | solidityBits<<CHUNK_SIDE_METADATA_BITS);
}

Solidity chunkSideSolidity(const ushort metadata, const CubeSide side)
{
	if (metadata & 0b1_00_00_00_00_00_00) // if metadata is presented
		return cast(Solidity)((metadata>>(side*2)) & 0b11);
	else
		return Solidity.transparent; // otherwise non-solid
}

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

// ditto
private ubyte calcSolidityBits(Layer)(Layer blockLayer, BlockInfoTable blockInfos)
	if (isSomeLayer!Layer)
{
	if (blockLayer.type == StorageType.uniform) {
		return calcSolidityBits(blockLayer.getUniform!BlockId, blockInfos);
	} else if (blockLayer.type == StorageType.fullArray) {
		BlockId[] blocks = blockLayer.getArray!BlockId;
		return calcSolidityBits(blocks, blockInfos);
	} else assert(false);
}

enum ubyte[3] solidity_bits = [0b001, 0b010, 0b100];
private ubyte calcSolidityBits(BlockId uniformBlock, BlockInfoTable blockInfos)
{
	Solidity solidity = blockInfos[uniformBlock].solidity;
	return solidity_bits[solidity];
}

private ubyte calcSolidityBits(BlockId[] blocks, BlockInfoTable blockInfos)
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

/// Returns true if chunk has blocks of specified solidity.
/// If metadata is invalid then chunk is assumed to have blocks of every solidity.
private bool hasSolidity(const ushort metadata, Solidity solidity)
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
private bool hasOnlySolidity(const ushort metadata, Solidity solidity)
{
	if (metadata & 0b1_00_00_00_00_00_00) {// if metadata is valid
		ubyte solidityBits = (metadata>>CHUNK_SIDE_METADATA_BITS) & 0b111;
		return solidityBits == (1 << solidity);
	} else {
		return false; // assume has every solidity.
	}
}

private bool[8] singleSolidityTable = [false, true, true, false, true, false, false, false];
private Solidity[8] bitsToSolidityTable = [Solidity.transparent, Solidity.transparent, Solidity.semiTransparent,
	Solidity.transparent, Solidity.solid, Solidity.transparent, Solidity.transparent, Solidity.transparent];

immutable ushort[3] solidity_metadatas = [0b1_00_00_00_00_00_00, 0b1_01_01_01_01_01_01, 0b1_10_10_10_10_10_10];

enum CHUNK_SIDE_METADATA_BITS = 13;
enum SOLID_CHUNK_METADATA = cast(ushort) (solidity_metadatas[Solidity.solid] |
		solidity_bits[Solidity.solid]<<CHUNK_SIDE_METADATA_BITS);
enum TRANSPARENT_CHUNK_METADATA = cast(ushort) (solidity_metadatas[Solidity.transparent] |
		solidity_bits[Solidity.transparent]<<CHUNK_SIDE_METADATA_BITS);

// calculate info about sides of chunk. 2 bits per side. Value is solidity.
private ushort calcChunkSideMetadata(Layer)(Layer blockLayer, BlockInfoTable blockInfos)
	if (isSomeLayer!Layer)
{
	if (blockLayer.type == StorageType.uniform) {
		return calcChunkSideMetadata(blockLayer.getUniform!BlockId, blockInfos);
	} else if (blockLayer.type == StorageType.fullArray) {
		BlockId[] blocks = blockLayer.getArray!BlockId;
		return calcChunkSideMetadata(blocks, blockInfos);
	} else assert(false);
}

// ditto
private ushort calcChunkSideMetadata(BlockId uniformBlock, BlockInfoTable blockInfos)
{
	Solidity solidity = blockInfos[uniformBlock].solidity;
	// 13th bit == 1 when metadata is present, 12 bits = solidity of 6 chunk sides. 2 bits per side
	return solidity_metadatas[solidity];
}

// ditto
private ushort calcChunkSideMetadata(BlockId[] blocks, BlockInfoTable blockInfos)
{
	ushort flags = 0b1_00_00_00_00_00_00; // all sides are solid
	Solidity sideSolidity = Solidity.solid;
	foreach(index; 0..CHUNK_SIZE_SQR) // yneg
	{
		if (sideSolidity > blockInfos[blocks[index]].solidity)
		{
			--sideSolidity;
			if (sideSolidity == Solidity.transparent)
				break;
		}
	}
	flags = cast(ushort)(flags | (sideSolidity << (CubeSide.yneg*2)));

	sideSolidity = Solidity.solid;
	outer_zneg:
	foreach(y; 0..CHUNK_SIZE)
	foreach(x; 0..CHUNK_SIZE)
	{
		size_t index = y*CHUNK_SIZE_SQR | x; // zneg
		if (sideSolidity > blockInfos[blocks[index]].solidity)
		{
			--sideSolidity;
			if (sideSolidity == Solidity.transparent)
				break outer_zneg;
		}
	}
	flags = cast(ushort)(flags | (sideSolidity << (CubeSide.zneg*2)));

	sideSolidity = Solidity.solid;
	outer_zpos:
	foreach(y; 0..CHUNK_SIZE)
	foreach(x; 0..CHUNK_SIZE)
	{
		size_t index = (CHUNK_SIZE-1) * CHUNK_SIZE | y*CHUNK_SIZE_SQR | x; // zpos
		if (sideSolidity > blockInfos[blocks[index]].solidity)
		{
			--sideSolidity;
			if (sideSolidity == Solidity.transparent)
				break outer_zpos;
		}
	}
	flags = cast(ushort)(flags | (sideSolidity << (CubeSide.zpos*2)));

	sideSolidity = Solidity.solid;
	outer_xpos:
	foreach(y; 0..CHUNK_SIZE)
	foreach(z; 0..CHUNK_SIZE)
	{
		size_t index = z * CHUNK_SIZE | y*CHUNK_SIZE_SQR | (CHUNK_SIZE-1); // xpos
		if (sideSolidity > blockInfos[blocks[index]].solidity)
		{
			--sideSolidity;
			if (sideSolidity == Solidity.transparent)
				break outer_xpos;
		}
	}
	flags = cast(ushort)(flags | (sideSolidity << (CubeSide.xpos*2)));

	sideSolidity = Solidity.solid;
	outer_xneg:
	foreach(y; 0..CHUNK_SIZE)
	foreach(z; 0..CHUNK_SIZE)
	{
		size_t index = z * CHUNK_SIZE | y*CHUNK_SIZE_SQR; // xneg
		if (sideSolidity > blockInfos[blocks[index]].solidity)
		{
			--sideSolidity;
			if (sideSolidity == Solidity.transparent)
				break outer_xneg;
		}
	}
	flags = cast(ushort)(flags | (sideSolidity << (CubeSide.xneg*2)));

	sideSolidity = Solidity.solid;
	foreach(index; CHUNK_SIZE_CUBE-CHUNK_SIZE_SQR..CHUNK_SIZE_CUBE) // ypos
	{
		if (sideSolidity > blockInfos[blocks[index]].solidity)
		{
			--sideSolidity;
			if (sideSolidity == Solidity.transparent)
				break;
		}
	}
	flags = cast(ushort)(flags | (sideSolidity << (CubeSide.ypos*2)));

	return flags;
}


/*
void iterateSides()
{
	foreach(index; 0..CHUNK_SIZE_SQR) // yneg

	{// zneg
		ubyte z = 0;
		foreach(y; 0..CHUNK_SIZE)
			foreach(x; 0..CHUNK_SIZE)
				index = z * CHUNK_SIZE | y*CHUNK_SIZE_SQR | x;
	}

	{// zpos
		ubyte z = CHUNK_SIZE-1;
		foreach(y; 0..CHUNK_SIZE)
			foreach(x; 0..CHUNK_SIZE)
				index = z * CHUNK_SIZE | y*CHUNK_SIZE_SQR | x;
	}

	{// xpos
		ubyte x = CHUNK_SIZE-1;
		foreach(y; 0..CHUNK_SIZE)
			foreach(z; 0..CHUNK_SIZE)
				index = z * CHUNK_SIZE | y*CHUNK_SIZE_SQR | x;
	}

	{// xneg
		ubyte x = 0;
		foreach(y; 0..CHUNK_SIZE)
			foreach(z; 0..CHUNK_SIZE)
				index = z * CHUNK_SIZE | y*CHUNK_SIZE_SQR | x;
	}

	foreach(index; CHUNK_SIZE_CUBE-CHUNK_SIZE_SQR..CHUNK_SIZE_CUBE) // ypos
}
*/
