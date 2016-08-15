/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.blockentity.blockentitydata;

import voxelman.math;

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
