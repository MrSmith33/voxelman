/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.blockentity.utils;

import voxelman.log;
import voxelman.container.buffer;
import voxelman.math;
import voxelman.geometry;

import voxelman.world.block;
import voxelman.core.config;
import voxelman.core.events;
import voxelman.world.storage;
import voxelman.world.mesh.chunkmesh;

import voxelman.world.blockentity;

enum BLOCK_ENTITY_FLAG = 1 << 15;
enum BLOCK_INDEX_MASK = (1 << 15) - 1;

pragma(inline, true)
bool isBlockEntity(BlockId blockId)
{
	enum n = BlockId.sizeof*8 - 1;
	return blockId >> n; // highest bit
}

ushort blockEntityIndexFromBlockId(BlockId blockId) {
	return blockId & BLOCK_INDEX_MASK;
}

BlockId blockIdFromBlockEntityIndex(ushort blockIndex) {
	return blockIndex | BLOCK_ENTITY_FLAG;
}

struct BlockEntityMeshingData
{
	Buffer!MeshVertex[] output;
	ubyte[4] delegate(ushort blockIndex, CubeSide side) occlusionHandler;
	ubvec3 color;
	ubyte sides;
	ivec3 chunkPos;
	ivec3 entityPos;
	BlockEntityData data;
	ushort blockIndex;
}

struct BlockEntityDebugContext
{
	import voxelman.graphics.plugin;
	BlockWorldPos bwp;
	BlockEntityData data;
	GraphicsPlugin graphics;
}

alias BlockEntityMeshhandler = void function(BlockEntityMeshingData);

alias SolidityHandler = Solidity function(CubeSide side, ivec3 chunkPos, ivec3 entityPos, BlockEntityData data);
alias BlockShapeHandler = BlockShape function(ivec3 chunkPos, ivec3 entityPos, BlockEntityData data);
alias EntityBoxHandler = WorldBox function(BlockWorldPos bwp, BlockEntityData data);
alias EntityDebugHandler = void function(ref BlockEntityDebugContext);
WorldBox nullBoxHandler(BlockWorldPos bwp, BlockEntityData data)
{
	return WorldBox(bwp.xyz, ivec3(1,1,1), cast(ushort)bwp.w);
}

void nullBlockEntityMeshhandler(BlockEntityMeshingData) {}

Solidity nullSolidityHandler(CubeSide side, ivec3 chunkPos, ivec3 entityPos, BlockEntityData data) {
	return Solidity.solid;
}

BlockShape nullBlockShapeHandler(ivec3 chunkPos, ivec3 entityPos, BlockEntityData data) {
	return fullShape;
}

struct BlockEntityInfo
{
	string name;
	BlockEntityMeshhandler meshHandler = &nullBlockEntityMeshhandler;
	SolidityHandler sideSolidity = &nullSolidityHandler;
	BlockShapeHandler blockShape = &nullBlockShapeHandler;
	EntityBoxHandler boxHandler = &nullBoxHandler;
	EntityDebugHandler debugHandler;
	ubvec3 color;
	//bool isVisible = true;
	size_t id;
}
BlockEntityInfo unknownBlockEntity = BlockEntityInfo("Unknown");

struct BlockEntityInfoTable
{
	immutable(BlockEntityInfo)[] blockEntityInfos;
	size_t length() {return blockEntityInfos.length; }
	BlockEntityInfo opIndex(ushort blockEntityId) {
		blockEntityId = blockEntityId;
		if (blockEntityId >= blockEntityInfos.length)
			return unknownBlockEntity;
		return blockEntityInfos[blockEntityId];
	}
}
