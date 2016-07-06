/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.blockentity.utils;

import std.experimental.logger;
import std.array : Appender;
import dlib.math.vector;
import voxelman.block.utils;
import voxelman.core.config;
import voxelman.core.events;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.worldbox;
import voxelman.core.chunkmesh;

import voxelman.blockentity.blockentityaccess;
import voxelman.blockentity.blockentitydata;

enum BLOCK_ENTITY_FLAG = 1 << 15;
enum BLOCK_INDEX_MASK = (1 << 15) - 1;

bool isBlockEntity(BlockId blockId)
{
	enum n = BlockId.sizeof*8 - 1;
	return blockId >> n; // highest bit
}

ushort blockIndexFromBlockId(BlockId blockId) {
	return blockId & BLOCK_INDEX_MASK;
}

BlockId blockIdFromBlockIndex(ushort blockIndex) {
	return blockIndex | BLOCK_ENTITY_FLAG;
}


alias BlockEntityMeshhandler = void function(
	Appender!(MeshVertex[])[] output,
	BlockEntityData data,
	ubyte[3] color,
	ubyte sides,
	//ivec3 worldPos,
	ivec3 chunkPos,
	ivec3 entityPos);

alias SolidityHandler = Solidity function(Side side);
alias EntityBoxHandler = WorldBox function(BlockWorldPos bwp, BlockEntityData data);
alias EntityDebugHandler = void function(BlockWorldPos bwp, BlockEntityData data);
WorldBox nullBoxHandler(BlockWorldPos bwp, BlockEntityData data)
{
	return WorldBox(bwp.xyz, ivec3(1,1,1), cast(ushort)bwp.w);
}

void nullBlockEntityMeshhandler(
	Appender!(MeshVertex[])[] output, BlockEntityData data,
	ubyte[3] color, ubyte sides, //ivec3 worldPos,
	ivec3 chunkPos, ivec3 entityPos) {}

Solidity nullSolidityHandler(Side side) {
	return Solidity.solid;
}

void nullDebugHandler(BlockWorldPos, BlockEntityData) {}

struct BlockEntityInfo
{
	string name;
	BlockEntityMeshhandler meshHandler = &nullBlockEntityMeshhandler;
	SolidityHandler sideSolidity = &nullSolidityHandler;
	EntityBoxHandler boxHandler = &nullBoxHandler;
	EntityDebugHandler debugHandler = &nullDebugHandler;
	ubyte[3] color;
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
