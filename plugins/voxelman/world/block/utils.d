/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.block.utils;

import voxelman.log;

import voxelman.container.buffer;
import voxelman.math;
import voxelman.geometry.cube;
import voxelman.core.config;
import voxelman.world.storage;
import voxelman.utils.mapping;
import voxelman.world.mesh.chunkmesh;


enum SideMask : ubyte
{
	zneg = 0b_00_0001,
	zpos = 0b_00_0010,

	xpos = 0b_00_0100,
	xneg = 0b_00_1000,

	ypos = 0b_01_0000,
	yneg = 0b_10_0000,
}

struct ChunkAndBlockAdjacent
{
	ubyte[27] chunks;
	ubyte[3][27] blocks;
}

struct ChunkAndBlockAt
{
	ubyte chunk;
	ubyte blockX, blockY, blockZ;
}

// 0-5 sides, or 6 if center
ChunkAndBlockAt chunkAndBlockAt6(int x, int y, int z)
{
	ubyte bx = cast(ubyte)x;
	ubyte by = cast(ubyte)y;
	ubyte bz = cast(ubyte)z;
	if(x == -1) return ChunkAndBlockAt(CubeSide.xneg, CHUNK_SIZE-1, by, bz);
	else if(x == CHUNK_SIZE) return ChunkAndBlockAt(CubeSide.xpos, 0, by, bz);

	if(y == -1) return ChunkAndBlockAt(CubeSide.yneg, bx, CHUNK_SIZE-1, bz);
	else if(y == CHUNK_SIZE) return ChunkAndBlockAt(CubeSide.ypos, bx, 0, bz);

	if(z == -1) return ChunkAndBlockAt(CubeSide.zneg, bx, by, CHUNK_SIZE-1);
	else if(z == CHUNK_SIZE) return ChunkAndBlockAt(CubeSide.zpos, bx, by, 0);

	return ChunkAndBlockAt(26, bx, by, bz);
}

// convert -1..33 -> 0..34 to use as index
ubyte[34] position_in_target_chunk = [CHUNK_SIZE-1, // CHUNK_SIZE-1 is in adjacent chunk
	0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,
	17,18,19,20,21,22,23,24,25,26,27,28,29,30,31, 0]; // 0 is in adjacent chunk
// 0 chunk in neg direction, 1 this chunk, 1 pos dir
ubyte[34] target_chunk =
[0, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 2];

ChunkAndBlockAt chunkAndBlockAt27(int x, int y, int z)
{
	ubyte bx = position_in_target_chunk[x+1];
	ubyte by = position_in_target_chunk[y+1];
	ubyte bz = position_in_target_chunk[z+1];

	ubyte cx = target_chunk[x+1];
	ubyte cy = target_chunk[y+1];
	ubyte cz = target_chunk[z+1];

	ubyte chunk_index = cast(ubyte)(cx + cz * 3 + cy * 9);

	return ChunkAndBlockAt(chunk_index, bx, by, bz);
}

CubeSide sideFromNormal(ivec3 normal)
{
	if (normal.x == 1)
		return CubeSide.xpos;
	else if (normal.x == -1)
		return CubeSide.xneg;

	if (normal.y == 1)
		return CubeSide.ypos;
	else if (normal.y == -1)
		return CubeSide.yneg;

	if (normal.z == 1)
		return CubeSide.zpos;
	else if (normal.z == -1)
		return CubeSide.zneg;

	return CubeSide.zneg;
}

float random(uint num)
{
	uint x = num;
	x = ((x >> 16) ^ x) * 0x45d9f3b;
	x = ((x >> 16) ^ x) * 0x45d9f3b;
	x = (x >> 16) ^ x;
	return (cast(float)x / uint.max);
}

struct MeshVertex2
{
	align(4):
	float x, y, z;
	ubyte[3] color;
}

void makeColoredBlockMesh(BlockMeshingData data)
{
	static immutable(float)[] shadowMultipliers = [
		0.7, 0.75, 0.6, 0.5, 0.85, 0.4,
	];

	float randomTint = random(data.index)*0.1+0.9;

	float r = data.color.r * randomTint;
	float g = data.color.g * randomTint;
	float b = data.color.b * randomTint;

	ubyte flag = 1;
	foreach(ubyte side; 0..6)
	{
		if (data.sides & flag)
		{
			ubyte[3] finalColor = [
				cast(ubyte)(shadowMultipliers[side] * r),
				cast(ubyte)(shadowMultipliers[side] * g),
				cast(ubyte)(shadowMultipliers[side] * b)];

			data.buffer.put(
				cast(MeshVertex)MeshVertex2(
					cubeFaces[18*side  ] + data.blockPos.x,
					cubeFaces[18*side+1] + data.blockPos.y,
					cubeFaces[18*side+2] + data.blockPos.z,
					finalColor),
				cast(MeshVertex)MeshVertex2(
					cubeFaces[18*side+3] + data.blockPos.x,
					cubeFaces[18*side+4] + data.blockPos.y,
					cubeFaces[18*side+5] + data.blockPos.z,
					finalColor),
				cast(MeshVertex)MeshVertex2(
					cubeFaces[18*side+6] + data.blockPos.x,
					cubeFaces[18*side+7] + data.blockPos.y,
					cubeFaces[18*side+8] + data.blockPos.z,
					finalColor),
				cast(MeshVertex)MeshVertex2(
					cubeFaces[18*side+9] + data.blockPos.x,
					cubeFaces[18*side+10] + data.blockPos.y,
					cubeFaces[18*side+11] + data.blockPos.z,
					finalColor),
				cast(MeshVertex)MeshVertex2(
					cubeFaces[18*side+12] + data.blockPos.x,
					cubeFaces[18*side+13] + data.blockPos.y,
					cubeFaces[18*side+14] + data.blockPos.z,
					finalColor),
				cast(MeshVertex)MeshVertex2(
					cubeFaces[18*side+15] + data.blockPos.x,
					cubeFaces[18*side+16] + data.blockPos.y,
					cubeFaces[18*side+17] + data.blockPos.z,
					finalColor)
			);
		} // if
		flag <<= 1;
	} // for side
}

ushort packColor(ubvec3 c) {
	return (c.r>>3) | (c.g&31) << 5 | (c.b&31) << 10;
}
ushort packColor(ubyte r, ubyte g, ubyte b) {
	return (r>>3) | (g&31) << 5 | (b&31) << 10;
}

alias BlockUpdateHandler = void delegate(BlockWorldPos bwp);
struct BlockMeshingData
{
	Buffer!MeshVertex* buffer;
	ubvec3 color;
	ubvec3 blockPos;
	ushort index;
	ubyte sides;
	Solidity[27]* solidities;
}
alias MeshHandler = void function(BlockMeshingData);
void makeNullMesh(BlockMeshingData) {}

alias SideSolidityHandler = Solidity function(CubeSide);
Solidity transparentSideSolidity(CubeSide) { return Solidity.transparent; }
Solidity semitransparentSideSolidity(CubeSide) { return Solidity.semiTransparent; }
Solidity solidSideSolidity(CubeSide) { return Solidity.solid; }

alias CornerSolidityHandler = Solidity function(CubeCorner);
Solidity transparentCornerSolidity(CubeCorner) { return Solidity.transparent; }
Solidity semitransparentCornerSolidity(CubeCorner) { return Solidity.semiTransparent; }
Solidity solidCornerSolidity(CubeCorner) { return Solidity.solid; }

// solidity number increases with solidity
enum Solidity : ubyte
{
	transparent,
	semiTransparent,
	solid,
}

bool isMoreSolidThan(Solidity first, Solidity second)
{
	return first > second;
}

struct BlockInfo
{
	string name;
	MeshHandler meshHandler = &makeNullMesh;
	ubvec3 color;
	bool isVisible = true;
	Solidity solidity = Solidity.solid;
	size_t id;

	SideSolidityHandler sideSolidity = &solidSideSolidity;
	CornerSolidityHandler cornerSolidity = &solidCornerSolidity;
	Solidity maxSolidity = Solidity.solid;
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

	ref BlockInfoSetter meshHandler(MeshHandler val) { info.meshHandler = val; return this; }
	ref BlockInfoSetter sideSolidity(SideSolidityHandler val) { info.sideSolidity = val; return this; }
	ref BlockInfoSetter cornerSolidity(CornerSolidityHandler val) { info.cornerSolidity = val; return this; }
	ref BlockInfoSetter color(ubyte[3] color ...) { info.color = ubvec3(color); return this; }
	ref BlockInfoSetter colorHex(uint hex) { info.color = ubvec3((hex>>16)&0xFF,(hex>>8)&0xFF,hex&0xFF); return this; }
	ref BlockInfoSetter isVisible(bool val) { info.isVisible = val; return this; }
	ref BlockInfoSetter solidity(Solidity val) {
		final switch (val) {
			case Solidity.transparent:
				info.sideSolidity = &transparentSideSolidity;
				info.cornerSolidity = &transparentCornerSolidity;
				break;
			case Solidity.semiTransparent:
				info.sideSolidity = &semitransparentSideSolidity;
				info.cornerSolidity = &semitransparentCornerSolidity;
				break;
			case Solidity.solid:
				info.sideSolidity = &solidSideSolidity;
				info.cornerSolidity = &solidCornerSolidity;
				break;
		}

		return this;
	}
}

void regBaseBlocks(BlockInfoSetter delegate(string name) regBlock)
{
	regBlock("unknown").color(0,0,0).isVisible(false).solidity(Solidity.solid).meshHandler(&makeNullMesh);
	regBlock("air").color(0,0,0).isVisible(false).solidity(Solidity.transparent).meshHandler(&makeNullMesh);
	regBlock("grass").colorHex(0x7EEE11).meshHandler(&makeColoredBlockMesh);
	regBlock("dirt").colorHex(0x835929).meshHandler(&makeColoredBlockMesh);
	regBlock("stone").colorHex(0x8B8D7A).meshHandler(&makeColoredBlockMesh);
	regBlock("sand").colorHex(0xA68117).meshHandler(&makeColoredBlockMesh);
	regBlock("water").colorHex(0x0055AA).meshHandler(&makeColoredBlockMesh).solidity(Solidity.semiTransparent);
	regBlock("lava").colorHex(0xFF6920).meshHandler(&makeColoredBlockMesh);
	regBlock("snow").colorHex(0xDBECF6).meshHandler(&makeColoredBlockMesh);
}
