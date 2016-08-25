/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.blockentity.blockentityaccess;

import std.experimental.logger;
import std.string;
import voxelman.math;
import voxelman.geometry.box;
import voxelman.core.config;
import voxelman.block.utils;
import voxelman.world.storage.chunk;
import voxelman.world.storage.chunkmanager;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.worldbox;
import voxelman.world.storage.worldaccess;
import voxelman.blockentity.plugin;

import voxelman.blockentity.blockentitymap;
import voxelman.blockentity.blockentitydata;


ushort boxEntityIndex(Box blockBox) {
	return BlockChunkIndex(blockBox.position).index;
}

ulong payloadFromIdAndEntityData(ushort id, ulong entityData) {
	ulong payload = cast(ulong)id << 46 | entityData & ENTITY_DATA_MASK;
	return payload;
}

// get chunk local piece of world space box
Box chunkLocalBlockBox(ChunkWorldPos cwp, Box blockBox) {
	Box chunkBlockBox = chunkToBlockBox(cwp);
	auto intersection = boxIntersection(chunkBlockBox, blockBox);
	assert(!intersection.empty);
	auto chunkLocalBox = intersection;
	chunkLocalBox.position -= chunkBlockBox.position;
	return chunkLocalBox;
}

void placeEntity(WorldBox blockBox, ulong payload,
	WorldAccess worldAccess, BlockEntityAccess entityAccess)
{
	auto mainCwp = ChunkWorldPos(BlockWorldPos(blockBox.position, blockBox.dimension));
	Box mainChunkBox = chunkLocalBlockBox(mainCwp, blockBox);
	ushort mainBlockIndex = boxEntityIndex(mainChunkBox);
	auto mainData = BlockEntityData(
		BlockEntityType.localBlockEntity, payload);

	Box affectedChunks = blockBoxToChunkBox(blockBox);
	ushort dimension = blockBox.dimension;
	foreach(chunkPos; affectedChunks.positions) {
		auto cwp = ChunkWorldPos(chunkPos, dimension);
		Box chunkLocalBox = chunkLocalBlockBox(cwp, blockBox);

		ushort blockIndex = boxEntityIndex(chunkLocalBox);
		BlockId blockId = blockIdFromBlockIndex(blockIndex);

		if (cwp == mainCwp)
		{
			entityAccess.setBlockEntity(cwp, mainBlockIndex, mainData);
		}
		else
		{
			ivec3 moff = cwp.xyz - mainCwp.xyz;
			ubyte[3] mainOffset = [cast(ubyte)moff.x,
				cast(ubyte)moff.y, cast(ubyte)moff.z];
			auto data = BlockEntityData(BlockEntityType.foreignBlockEntity,
				mainData.id, mainOffset, mainBlockIndex);
			entityAccess.setBlockEntity(cwp, blockIndex, data);
		}
		worldAccess.fillChunkBox(cwp, chunkLocalBox, blockId);
	}
}

void placeChunkEntity(WorldBox blockBox, ulong payload,
	WorldAccess worldAccess, BlockEntityAccess entityAccess)
{
	auto corner = BlockWorldPos(blockBox.position, blockBox.dimension);
	auto cwp = ChunkWorldPos(corner);

	// limit entity to a single chunk
	Box chunkLocalBox = chunkLocalBlockBox(cwp, blockBox);

	ushort blockIndex = boxEntityIndex(chunkLocalBox);
	BlockId blockId = blockIdFromBlockIndex(blockIndex);
	worldAccess.fillChunkBox(cwp, chunkLocalBox, blockId);
	auto beData = BlockEntityData(BlockEntityType.localBlockEntity, payload);
	bool placed = entityAccess.setBlockEntity(cwp, blockIndex, beData);
}

WorldBox getBlockEntityBox(ChunkWorldPos cwp, ushort blockIndex,
	BlockEntityInfoTable blockEntityInfos, BlockEntityAccess entityAccess)
{
	BlockEntityData entity = entityAccess.getBlockEntity(cwp, blockIndex);

	with(BlockEntityType) final switch(entity.type)
	{
		case localBlockEntity:
			BlockEntityInfo eInfo = blockEntityInfos[entity.id];
			auto entityBwp = BlockWorldPos(cwp, blockIndex);
			WorldBox eVol = eInfo.boxHandler(entityBwp, entity);
			return eVol;
		case foreignBlockEntity:
			auto mainPtr = entity.mainChunkPointer;
			auto mainCwp = ChunkWorldPos(ivec3(cwp.xyz) - mainPtr.mainChunkOffset, cwp.w);
			BlockEntityData mainEntity = entityAccess.getBlockEntity(mainCwp, mainPtr.blockIndex);
			auto mainBwp = BlockWorldPos(mainCwp, mainPtr.blockIndex);

			BlockEntityInfo eInfo = blockEntityInfos[mainPtr.entityId];
			WorldBox eVol = eInfo.boxHandler(mainBwp, mainEntity);
			return eVol;
	}
}

/// Returns changed box
WorldBox removeEntity(BlockWorldPos bwp, BlockEntityInfoTable beInfos,
	WorldAccess worldAccess, BlockEntityAccess entityAccess,
	BlockId fillerBlock)
{
	BlockId blockId = worldAccess.getBlock(bwp);
	if (!isBlockEntity(blockId))
		return WorldBox();

	auto mainCwp = ChunkWorldPos(bwp);
	ushort mainBlockIndex = blockIndexFromBlockId(blockId);
	WorldBox blockBox = getBlockEntityBox(mainCwp, mainBlockIndex, beInfos, entityAccess);

	Box affectedChunks = blockBoxToChunkBox(blockBox);
	ushort dimension = blockBox.dimension;
	foreach(chunkPos; affectedChunks.positions) {
		auto cwp = ChunkWorldPos(chunkPos, dimension);
		Box chunkLocalBox = chunkLocalBlockBox(cwp, blockBox);

		ushort blockIndex = boxEntityIndex(chunkLocalBox);

		entityAccess.removeEntity(cwp, blockIndex);
		worldAccess.fillChunkBox(cwp, chunkLocalBox, fillerBlock);
	}

	return blockBox;
}

final class BlockEntityAccess
{
	private ChunkManager chunkManager;

	this(ChunkManager chunkManager) {
		this.chunkManager = chunkManager;
	}

	bool setBlockEntity(ChunkWorldPos cwp, ushort blockIndex, BlockEntityData beData)
	{
		assert((blockIndex & BLOCK_ENTITY_FLAG) == 0);
		if (!chunkManager.isChunkLoaded(cwp)) return false;

		WriteBuffer* writeBuffer = chunkManager.getOrCreateWriteBuffer(cwp,
				ENTITY_LAYER, WriteBufferPolicy.copySnapshotArray);
		assert(writeBuffer);

		BlockEntityMap map = getHashMapFromLayer(writeBuffer.layer);
		map[blockIndex] = beData.storage;
		setLayerMap(writeBuffer.layer, map);
		return true;
	}

	BlockEntityData getBlockEntity(ChunkWorldPos cwp, ushort blockIndex)
	{
		assert((blockIndex & BLOCK_ENTITY_FLAG) == 0);
		auto entities = chunkManager.getChunkSnapshot(cwp, ENTITY_LAYER, Yes.Uncompress);
		if (entities.isNull) return BlockEntityData.init;
		if (entities.type == StorageType.uniform) return BlockEntityData.init;

		BlockEntityMap map = getHashMapFromLayer(entities);

		ulong* entity = blockIndex in map;
		if (entity is null) return BlockEntityData.init;

		return BlockEntityData(*entity);
	}

	bool removeEntity(ChunkWorldPos cwp, ushort blockIndex)
	{
		assert((blockIndex & BLOCK_ENTITY_FLAG) == 0);
		if (!chunkManager.isChunkLoaded(cwp)) return false;

		WriteBuffer* writeBuffer = chunkManager.getOrCreateWriteBuffer(cwp,
				ENTITY_LAYER, WriteBufferPolicy.copySnapshotArray);
		assert(writeBuffer);

		BlockEntityMap map = getHashMapFromLayer(writeBuffer.layer);

		map.remove(blockIndex);
		setLayerMap(writeBuffer.layer, map);
		return true;
	}
}

void setLayerMap(Layer)(ref Layer layer, BlockEntityMap map) {
	ubyte[] arr = map.getTable();
	layer.dataPtr = arr.ptr;
	layer.dataLength = cast(LayerDataLenType)arr.length;
	layer.metadata = cast(ushort)map.length;
}

BlockEntityMap getHashMapFromLayer(Layer)(const ref Layer layer) {
	if (layer.type == StorageType.uniform)
		return BlockEntityMap();
	return BlockEntityMap(layer.getArray!ubyte, layer.metadata);
}
