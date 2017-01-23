/**
Copyright: Copyright (c) 2013-2017 Andrey Penechko.
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
import voxelman.world.block;
import voxelman.world.mesh.chunkmesh;


struct ChunkAndBlockAdjacent
{
	ubyte[27] chunks;
	ubyte[3][27] blocks;
}

struct ChunkAndBlockAt
{
	ubyte chunk;
	// position of block in chunk
	ubyte bx, by, bz;
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

struct MeshVertex2
{
	align(4):
	float x, y, z;
	ubyte[3] color;
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
	ubyte[4] delegate(ushort blockIndex, CubeSide side) occlusionHandler;
	ubvec3 color;
	ubvec3 chunkPos;
	ubyte sides;
	ushort blockIndex;
	BlockMetadata metadata;
}
alias MeshHandler = void function(BlockMeshingData);
alias ShapeMetaHandler = BlockShape function(BlockMetadata);
alias RotationHandler = BlockMetadata function(BlockMetadata);
void makeNullMesh(BlockMeshingData) {}

alias SideSolidityHandler = Solidity function(CubeSide);
Solidity transparentSideSolidity(CubeSide) { return Solidity.transparent; }
Solidity semitransparentSideSolidity(CubeSide) { return Solidity.semiTransparent; }
Solidity solidSideSolidity(CubeSide) { return Solidity.solid; }

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
	BlockShape shape = fullShape;
	ShapeMetaHandler shapeMetaHandler;
	RotationHandler rotationHandler;
	bool shapeDependsOnMeta = false;
	bool meshDependOnMeta = false;
	size_t id;
}

BlockInfo entityBlock = BlockInfo("Entity", &makeColoredFullBlockMesh);
struct BlockInfoTable
{
	immutable(BlockInfo)[] blockInfos;
	SideIntersectionTable sideTable;

	size_t length() {return blockInfos.length; }

	BlockInfo opIndex(BlockId blockId) {
		if (blockId >= blockInfos.length)
			return entityBlock;
		return blockInfos[blockId];
	}
}

struct SeparatedBlockInfoTable
{
	this(BlockInfoTable infoTable)
	{
		sideTable = infoTable.sideTable;
		shape.length = infoTable.length;
		corners.length = infoTable.length;
		hasGeometry.length = infoTable.length;
		hasInternalGeometry.length = infoTable.length;
		sideMasks.length = infoTable.length;
		color.length = infoTable.length;
		meshHandler.length = infoTable.length;
		shapeMetaHandler.length = infoTable.length;
		shapeDependsOnMeta.length = infoTable.length;
		meshDependOnMeta.length = infoTable.length;

		foreach(i, binfo; infoTable.blockInfos)
		{
			shape[i] = binfo.shape;
			corners[i] = binfo.shape.corners;
			hasGeometry[i] = binfo.shape.hasGeometry;
			hasInternalGeometry[i] = binfo.shape.hasInternalGeometry;
			sideMasks[i] = binfo.shape.sideMasks;
			color[i] = binfo.color;
			meshHandler[i] = binfo.meshHandler;
			shapeMetaHandler[i] = binfo.shapeMetaHandler;
			shapeDependsOnMeta[i] = binfo.shapeDependsOnMeta;
			meshDependOnMeta[i] = binfo.meshDependOnMeta;
		}

		blockInfos = infoTable.blockInfos;
	}

	immutable(BlockInfo)[] blockInfos;
	SideIntersectionTable sideTable;
	BlockShape[] shape;
	ubyte[] corners;
	bool[] hasGeometry;
	bool[] hasInternalGeometry;
	bool[] shapeDependsOnMeta;
	bool[] meshDependOnMeta;
	ShapeSideMask[6][] sideMasks;
	ubvec3[] color;
	MeshHandler[] meshHandler;
	ShapeMetaHandler[] shapeMetaHandler;
}

/// Returned when registering block.
/// Use this to set block properties.
struct BlockInfoSetter
{
	private Mapping!(BlockInfo)* mapping;
	private size_t blockId;
	private ref BlockInfo info() {return (*mapping)[blockId]; }

	ref BlockInfoSetter meshHandler(MeshHandler val) { info.meshHandler = val; return this; }
	ref BlockInfoSetter color(ubyte[3] color ...) { info.color = ubvec3(color); return this; }
	ref BlockInfoSetter colorHex(uint hex) { info.color = ubvec3((hex>>16)&0xFF,(hex>>8)&0xFF,hex&0xFF); return this; }
	ref BlockInfoSetter isVisible(bool val) { info.isVisible = val; return this; }
	ref BlockInfoSetter solidity(Solidity val) { info.solidity = val; return this; }
	ref BlockInfoSetter blockShape(BlockShape val) { info.shape = val; return this; }
	ref BlockInfoSetter shapeMetaHandler(ShapeMetaHandler val) {
		info.shapeMetaHandler = val;
		info.shapeDependsOnMeta = true;
		return this;
	}
	//ref BlockInfoSetter shapeDependsOnMeta(bool val) { info.shapeDependsOnMeta = val; return this; }
	ref BlockInfoSetter meshDependOnMeta(bool val) { info.meshDependOnMeta = val; return this; }
	ref BlockInfoSetter rotationHandler(RotationHandler val) { info.rotationHandler = val; return this; }
}

import voxelman.world.mesh.blockmeshers.full;
import voxelman.world.mesh.blockmeshers.slope;

void regBaseBlocks(BlockInfoSetter delegate(string name) regBlock)
{
	regBlock("unknown").color(0,0,0).isVisible(false).solidity(Solidity.solid).meshHandler(&makeNullMesh).blockShape(unknownShape);
	regBlock("air").color(0,0,0).isVisible(false).solidity(Solidity.transparent).meshHandler(&makeNullMesh).blockShape(emptyShape);
	regBlock("grass").colorHex(0x01A611).meshHandler(&makeColoredFullBlockMesh);
	regBlock("dirt").colorHex(0x835929).meshHandler(&makeColoredFullBlockMesh);
	regBlock("stone").colorHex(0x8B8D7A).meshHandler(&makeColoredFullBlockMesh);
	regBlock("sand").colorHex(0xA68117).meshHandler(&makeColoredFullBlockMesh);
	regBlock("water").colorHex(0x0055AA).meshHandler(&makeColoredFullBlockMesh).solidity(Solidity.semiTransparent).blockShape(waterShape);
	regBlock("lava").colorHex(0xFF6920).meshHandler(&makeColoredFullBlockMesh);
	regBlock("snow").colorHex(0xDBECF6).meshHandler(&makeColoredFullBlockMesh);
	regBlock("slope").colorHex(0x857FFF).meshHandler(&makeColoredSlopeBlockMesh).shapeMetaHandler(&slopeShapeFromMeta)
		.meshDependOnMeta(true).rotationHandler(&slopeRotationHandler);
}

void setSideTable(ref SideIntersectionTable sideTable)
{
	sideTable.set(ShapeSideMask.full, ShapeSideMask.empty);
	sideTable.set(ShapeSideMask.water, ShapeSideMask.empty);
	sideTable.set(ShapeSideMask.full, ShapeSideMask.water);

	sideTable.set(ShapeSideMask.water, ShapeSideMask.slope0);
	sideTable.set(ShapeSideMask.full, ShapeSideMask.slope0);
	sideTable.set(ShapeSideMask.water, ShapeSideMask.slope1);
	sideTable.set(ShapeSideMask.full, ShapeSideMask.slope1);
	sideTable.set(ShapeSideMask.water, ShapeSideMask.slope2);
	sideTable.set(ShapeSideMask.full, ShapeSideMask.slope2);
	sideTable.set(ShapeSideMask.water, ShapeSideMask.slope3);
	sideTable.set(ShapeSideMask.full, ShapeSideMask.slope3);

	sideTable.set(ShapeSideMask.slope0, ShapeSideMask.slope0);
	sideTable.set(ShapeSideMask.slope0, ShapeSideMask.slope1);
	sideTable.set(ShapeSideMask.slope0, ShapeSideMask.slope2);
	sideTable.set(ShapeSideMask.slope0, ShapeSideMask.empty);
	sideTable.set(ShapeSideMask.slope0, ShapeSideMask.water);

	sideTable.set(ShapeSideMask.slope1, ShapeSideMask.slope0);
	sideTable.set(ShapeSideMask.slope1, ShapeSideMask.slope1);
	sideTable.set(ShapeSideMask.slope1, ShapeSideMask.slope3);
	sideTable.set(ShapeSideMask.slope1, ShapeSideMask.empty);
	sideTable.set(ShapeSideMask.slope1, ShapeSideMask.water);

	sideTable.set(ShapeSideMask.slope2, ShapeSideMask.slope0);
	sideTable.set(ShapeSideMask.slope2, ShapeSideMask.slope2);
	sideTable.set(ShapeSideMask.slope2, ShapeSideMask.slope3);
	sideTable.set(ShapeSideMask.slope2, ShapeSideMask.empty);
	sideTable.set(ShapeSideMask.slope2, ShapeSideMask.water);

	sideTable.set(ShapeSideMask.slope3, ShapeSideMask.slope1);
	sideTable.set(ShapeSideMask.slope3, ShapeSideMask.slope2);
	sideTable.set(ShapeSideMask.slope3, ShapeSideMask.slope3);
	sideTable.set(ShapeSideMask.slope3, ShapeSideMask.empty);
	sideTable.set(ShapeSideMask.slope3, ShapeSideMask.water);

}

BlockMetadata slopeRotationHandler(BlockMetadata meta)
{
	if (meta == 11) return 0;
	return cast(BlockMetadata)(meta + 1);
}
