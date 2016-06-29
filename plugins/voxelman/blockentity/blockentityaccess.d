/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.blockentity.blockentityaccess;

import std.experimental.logger;
import std.string;
import voxelman.core.config;
import voxelman.block.utils;
import voxelman.world.storage.chunk;
import voxelman.world.storage.chunkmanager;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.volume;
import voxelman.world.storage.worldaccess;
import voxelman.blockentity.plugin;

import voxelman.blockentity.blockentitymap;

enum BlockEntityType : ubyte
{
	localBlockEntity,
	foreignBlockEntity,
	//componentId
}

enum ENTITY_DATA_MASK = (1UL << 46) - 1;
enum PAYLOAD_MASK = (1UL << 62) - 1;

// 3 bytes from LSB side
enum MAIN_OFFSET_BITS = 8*3;
enum MAIN_OFFSET_MASK = (1 << MAIN_OFFSET_BITS) - 1;
// ushort for block index
enum MAIN_BLOCK_INDEX_MASK = ushort.max;

/// Layout (bit fields, MSB -> LSB)
/// 2: type; 16 id + 46 entityData = 62 payload
/// data is:
/// localBlockEntity: entity id + data in payload
/// foreignBlockEntity: position of localBlockEntity (relative to current entity)
/// componentId: id in component system
struct BlockEntityData
{
	ulong storage;

	this(ulong data) {
		storage = data;
	}
	this(BlockEntityType type, ushort id, ulong entityData) {
		storage = cast(ulong)type << 62 | cast(ulong)id << 46 |
			entityData & ENTITY_DATA_MASK;
	}
	this(BlockEntityType type, ushort id, ubyte[3] mainOffset, ushort blockIndex) {
		storage =
			cast(ulong)type << 62 |
			cast(ulong)id << 46 |
			(cast(ulong)blockIndex << MAIN_OFFSET_BITS) |
			(cast(ulong)mainOffset[0]) |
			(cast(ulong)mainOffset[1] << 8) |
			(cast(ulong)mainOffset[2] << 16);
	}
	this(BlockEntityType type, ulong payload) {
		storage = cast(ulong)type << 62 |
			payload & PAYLOAD_MASK;
	}

	BlockEntityType type() { return cast(BlockEntityType)(storage >> 62); }
	ushort id() { return cast(ushort)(storage >> 46); }
	ulong entityData() { return storage & ENTITY_DATA_MASK; }
	ulong payload() { return storage & PAYLOAD_MASK; }
	MainChunkPointer mainChunkPointer() {
		MainChunkPointer res;
		res.entityId = id;

		ulong offData = storage & MAIN_OFFSET_MASK;
		res.mainChunkOffset = ivec3(*cast(ubyte[3]*)&offData);
		res.blockIndex = (storage >> MAIN_OFFSET_BITS) & MAIN_BLOCK_INDEX_MASK;

		return res;
	}
}

ivec3 entityDataToSize(ulong entityData) {
	enum MASK_8_BIT = (1<<8) - 1;
	uint x = entityData & MASK_8_BIT;
	uint y = (entityData >> 8) & MASK_8_BIT;
	uint z = (entityData >> 16) & MASK_8_BIT;
	return ivec3(x, y, z);
}

ulong sizeToEntityData(ivec3 size) {
	enum MASK_8_BIT = (1<<8) - 1;
	ulong x = cast(ulong)size.x & MASK_8_BIT;
	ulong y = (cast(ulong)size.y & MASK_8_BIT) << 8;
	ulong z = (cast(ulong)size.z & MASK_8_BIT) << 16;
	return x | y | z;
}

// data assigned to foreign chunk of multichunk entity.
struct MainChunkPointer
{
	// offset in chunk coords from main chunk that contains entity data.
	// mainChunkOffset = otherPos - mainPos;
	// mainPos = otherPos - mainChunkOffset
	ivec3 mainChunkOffset;
	// block index in main chunk. Can be used as key to entity map in main chunk.
	ushort blockIndex;
	// id of the whole block entity.
	ushort entityId;
}

ushort volumeEntityIndex(Volume blockVolume) {
	return BlockChunkIndex(blockVolume.position).index;
}

ulong payloadFromIdAndEntityData(ushort id, ulong entityData) {
	ulong payload = cast(ulong)id << 46 | entityData & ENTITY_DATA_MASK;
	return payload;
}

// get chunk local piece of world space volume
Volume chunkLocalBlockVolume(ChunkWorldPos cwp, Volume blockVolume) {
	Volume chunkBlockVolume = chunkToBlockVolume(cwp);
	auto intersection = volumeIntersection(chunkBlockVolume, blockVolume);
	assert(!intersection.empty);
	auto chunkLocalVolume = intersection;
	chunkLocalVolume.position -= chunkBlockVolume.position;
	return chunkLocalVolume;
}

void placeEntity(Volume blockVolume, ulong payload,
	WorldAccess worldAccess, BlockEntityAccess entityAccess)
{
	auto mainCwp = ChunkWorldPos(BlockWorldPos(blockVolume.position, blockVolume.dimention));
	Volume mainChunkVolume = chunkLocalBlockVolume(mainCwp, blockVolume);
	ushort mainBlockIndex = volumeEntityIndex(mainChunkVolume);
	auto mainData = BlockEntityData(
		BlockEntityType.localBlockEntity, payload);

	Volume affectedChunks = blockVolumeToChunkVolume(blockVolume);
	ushort dimention = blockVolume.dimention;
	foreach(chunkPos; affectedChunks.positions) {
		auto cwp = ChunkWorldPos(chunkPos, dimention);
		Volume chunkLocalVolume = chunkLocalBlockVolume(cwp, blockVolume);

		ushort blockIndex = volumeEntityIndex(chunkLocalVolume);
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
		worldAccess.fillChunkVolume(cwp, chunkLocalVolume, blockId);
	}
}

void placeChunkEntity(Volume blockVolume, ulong payload,
	WorldAccess worldAccess, BlockEntityAccess entityAccess)
{
	auto corner = BlockWorldPos(blockVolume.position, blockVolume.dimention);
	auto cwp = ChunkWorldPos(corner);

	// limit entity to a single chunk
	Volume chunkLocalVolume = chunkLocalBlockVolume(cwp, blockVolume);

	ushort blockIndex = volumeEntityIndex(chunkLocalVolume);
	BlockId blockId = blockIdFromBlockIndex(blockIndex);
	worldAccess.fillChunkVolume(cwp, chunkLocalVolume, blockId);
	auto beData = BlockEntityData(BlockEntityType.localBlockEntity, payload);
	bool placed = entityAccess.setBlockEntity(cwp, blockIndex, beData);
}

Volume getBlockEntityVolume(ChunkWorldPos cwp, ushort blockIndex,
	BlockEntityInfoTable blockEntityInfos, BlockEntityAccess entityAccess)
{
	BlockEntityData entity = entityAccess.getBlockEntity(cwp, blockIndex);

	with(BlockEntityType) final switch(entity.type)
	{
		case localBlockEntity:
			BlockEntityInfo eInfo = blockEntityInfos[entity.id];
			auto entityBwp = BlockWorldPos(cwp, blockIndex);
			Volume eVol = eInfo.boxHandler(entityBwp, entity);
			return eVol;
		case foreignBlockEntity:
			auto mainPtr = entity.mainChunkPointer;
			auto mainCwp = ChunkWorldPos(ivec3(cwp.xyz) - mainPtr.mainChunkOffset, cwp.w);
			BlockEntityData mainEntity = entityAccess.getBlockEntity(mainCwp, mainPtr.blockIndex);
			auto mainBwp = BlockWorldPos(mainCwp, mainPtr.blockIndex);

			BlockEntityInfo eInfo = blockEntityInfos[mainPtr.entityId];
			Volume eVol = eInfo.boxHandler(mainBwp, mainEntity);
			return eVol;
	}
}

/// Returns changed volume
Volume removeEntity(BlockWorldPos bwp, BlockEntityInfoTable beInfos,
	WorldAccess worldAccess, BlockEntityAccess entityAccess,
	BlockId fillerBlock)
{
	BlockId blockId = worldAccess.getBlock(bwp);
	if (!isBlockEntity(blockId))
		return Volume();

	auto mainCwp = ChunkWorldPos(bwp);
	ushort mainBlockIndex = blockIndexFromBlockId(blockId);
	Volume blockVolume = getBlockEntityVolume(mainCwp, mainBlockIndex, beInfos, entityAccess);

	Volume affectedChunks = blockVolumeToChunkVolume(blockVolume);
	ushort dimention = blockVolume.dimention;
	foreach(chunkPos; affectedChunks.positions) {
		auto cwp = ChunkWorldPos(chunkPos, dimention);
		Volume chunkLocalVolume = chunkLocalBlockVolume(cwp, blockVolume);

		ushort blockIndex = volumeEntityIndex(chunkLocalVolume);

		entityAccess.removeEntity(cwp, blockIndex);
		worldAccess.fillChunkVolume(cwp, chunkLocalVolume, fillerBlock);
	}

	return blockVolume;
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
		setLayer(writeBuffer.layer, map);
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
		setLayer(writeBuffer.layer, map);
		return true;
	}
}

void setLayer(Layer)(ref Layer layer, BlockEntityMap map) {
	ubyte[] arr = cast(ubyte[])map.getTable();
	layer.dataPtr = arr.ptr;
	layer.dataLength = cast(LayerDataLenType)arr.length;
	layer.metadata = cast(ushort)map.length;
}

BlockEntityMap getHashMapFromLayer(Layer)(const ref Layer layer) {
	if (layer.type == StorageType.uniform)
		return BlockEntityMap();
	return BlockEntityMap(layer.getArray!ubyte, layer.metadata);
}
