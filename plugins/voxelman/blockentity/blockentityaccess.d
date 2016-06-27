/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
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

enum BlockEntityType : ubyte
{
	localBlockEntity,
	foreignBlockEntity,
	componentId
}

enum ENTITY_DATA_MASK = (1UL << 46) - 1;
enum PAYLOAD_MASK = (1UL << 62) - 1;
enum BLOCK_INDEX_MASK = (1 << 15) - 1;
enum BLOCK_ENTITY_FLAG = 1 << 16;

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
	this(BlockEntityType type, ulong payload) {
		storage = cast(ulong)type << 62 |
			payload & PAYLOAD_MASK;
	}

	BlockEntityType type() { return cast(BlockEntityType)(storage >> 62); }
	ushort id() { return cast(ushort)(storage >> 46); }
	ulong entityData() { return storage & ENTITY_DATA_MASK; }
	ulong payload() { return storage & PAYLOAD_MASK; }
}

BlockId volumeEntityIndex(Volume blockVolume) {
	BlockId blockId = BlockChunkIndex(blockVolume.position).index;
	blockId |= staticEntityBit;
	return blockId;
}

ushort blockIndexFromBlockId(BlockId blockId) {
	return blockId & BLOCK_INDEX_MASK;
}

ulong payloadFromIdAndEntityData(ushort id, ulong entityData) {
	ulong payload = cast(ulong)id << 46 | entityData & ENTITY_DATA_MASK;
	return payload;
}

void placeEntity(Volume blockVolume, BlockEntityData beData,
	WorldAccess worldAccess, BlockEntityAccess entityAccess)
{
	auto corner = BlockWorldPos(blockVolume.position, blockVolume.dimention);
	auto cwp = ChunkWorldPos(corner);

	// limit entity to one a single
	Volume chunkBlockVolume = chunkToBlockVolume(cwp);
	auto intersection = volumeIntersection(chunkBlockVolume, blockVolume);
	auto chunkLocalVolume = intersection;
	chunkLocalVolume.position -= chunkBlockVolume.position;

	ushort blockIndex = volumeEntityIndex(chunkLocalVolume);
	worldAccess.fillChunkVolume(cwp, chunkLocalVolume, blockIndex);
	bool placed = entityAccess.setBlockEntity(cwp, blockIndex, beData);

	//if (placed)
	//	infof("Placed entity at %s with payload %s (id %s, data %s)",
	//		blockId, beData.payload, beData.id, beData.entityData);
}

/// Returns changed volume
Volume removeEntity(BlockWorldPos bwp, BlockEntityInfoTable beInfos,
	WorldAccess worldAccess, BlockEntityAccess entityAccess,
	BlockId fillerBlock)
{
	auto cwp = ChunkWorldPos(bwp);
	//ushort blockIndex = BlockChunkIndex(BlockChunkPos(bwp)).index;

	BlockId blockId = worldAccess.getBlock(bwp);
	if (!isBlockEntity(blockId))
		return Volume();
	ushort blockIndex = blockIndexFromBlockId(blockId);
	auto entityBwp = BlockWorldPos(cwp, blockIndex);

	BlockEntityData beData = entityAccess.getBlockEntity(cwp, blockIndex);
	// box should start at bwp
	Volume entityBox;
	with(BlockEntityType) final switch(beData.type) {
		case localBlockEntity:
			entityBox = beInfos[beData.id].boxHandler(entityBwp, beData);
			break;
		case foreignBlockEntity:
			entityBox = unknownBlockEntity.boxHandler(entityBwp, beData);
			break;
		case componentId:
			entityBox = unknownBlockEntity.boxHandler(entityBwp, beData);
			break;
	}

	//infof("Remove entity pos %s box %s %s", bwp, entityBox, cwp);

	Volume chunkEntityVol = blockVolumeToChunkLocalVolume(entityBox);
	worldAccess.fillChunkVolume(cwp, chunkEntityVol, fillerBlock);
	entityAccess.removeEntity(cwp, blockIndex);
	return entityBox;
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

		auto map = getHashMapFromLayer(writeBuffer.layer);
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

		auto map = getHashMapFromLayer(entities);

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

		auto map = getHashMapFromLayer(writeBuffer.layer);
		map.remove(blockIndex);
		setLayer(writeBuffer.layer, map);
		return true;
	}
}

void setLayer(Layer)(ref Layer layer, HashMap map) {
	ubyte[] arr = cast(ubyte[])map.getTable();
	layer.dataPtr = arr.ptr;
	layer.dataLength = cast(LayerDataLenType)arr.length;
	layer.metadata = cast(ushort)map.length;
}

HashMap getHashMapFromLayer(Layer)(const ref Layer layer) {
	if (layer.type == StorageType.uniform)
		return HashMap();
	return HashMap(layer.getArray!ubyte, layer.metadata);
}

T nextPOT(T)(T x) {
	--x;
	x |= x >> 1;
	x |= x >> 2;
	x |= x >> 4;
	static if (T.sizeof >= 16) x |= x >>  8;
	static if (T.sizeof >= 32) x |= x >> 16;
	static if (T.sizeof >= 64) x |= x >> 32;
	++x;

	return x;
}

unittest {
	assert(nextPOT(1) == 1);
	assert(nextPOT(2) == 2);
	assert(nextPOT(3) == 4);
	assert(nextPOT(4) == 4);
	assert(nextPOT(5) == 8);
	assert(nextPOT(10) == 16);
	assert(nextPOT(30) == 32);
	assert(nextPOT(250) == 256);
	assert(nextPOT(1<<15+1) == 1<<16);
	assert(nextPOT(1UL<<31+1) == 1UL<<32);
	assert(nextPOT(1UL<<49+1) == 1UL<<50);
}

struct HashMap
{
	import std.experimental.allocator.gc_allocator;
	import std.experimental.allocator.mallocator;

	alias Key = ushort;
	alias Value = ulong;
	Key[] keys;
	Value[] values;
	size_t length;

	private bool resizing;
	enum nullKey = ushort.max;

	//alias allocator = Mallocator.instance;
	alias allocator = GCAllocator.instance;

	this(ubyte[] array, ushort length) {
		if (array.length % (Key.sizeof + Value.sizeof))
			infof("size %s", array.length);
		size_t size = array.length / (Key.sizeof + Value.sizeof);
		keys = cast(Key[])array[0..Key.sizeof * size];
		values = cast(Value[])array[Key.sizeof * size..$];
		this.length = length;
	}

	ubyte[] getTable() {
		return (cast(ubyte[])keys).ptr[0..(Key.sizeof + Value.sizeof) * keys.length];
	}

	@property size_t capacity() const { return keys.length; }

	void remove(ushort key) {
		auto idx = findIndex(key);
		if (idx == size_t.max) return;
		auto i = idx;
		while (true)
		{
			keys[i] = nullKey;

			size_t j = i, r;
			do {
				if (++i >= keys.length) i -= keys.length;
				if (keys[i] == nullKey)
				{
					--length;
					return;
				}
				r = keys[i] & (keys.length-1);
			}
			while ((j<r && r<=i) || (i<j && j<r) || (r<=i && i<j));
			keys[j] = keys[i];
			values[j] = values[i];
		}
	}

	Value get(ushort key, Value default_value = Value.init) {
		auto idx = findIndex(key);
		if (idx == size_t.max) return default_value;
		return values[idx];
	}

	void clear() {
		keys[] = nullKey;
		length = 0;
	}

	void opIndexAssign(Value value, ushort key) {
		grow(1);
		auto i = findInsertIndex(key);
		if (keys[i] != key) length++;
		keys[i] = key;
		values[i] = value;
	}

	ref inout(Value) opIndex(ushort key) inout {
		auto idx = findIndex(key);
		assert (idx != size_t.max, "Accessing non-existent key.");
		return values[idx];
	}

	inout(Value)* opBinaryRight(string op)(ushort key) inout if (op == "in") {
		auto idx = findIndex(key);
		if (idx == size_t.max) return null;
		return &values[idx];
	}

	int opApply(int delegate(ref Value) del) {
		foreach (i; 0 .. keys.length)
			if (keys[i] != nullKey)
				if (auto ret = del(values[i]))
					return ret;
		return 0;
	}

	int opApply(int delegate(in ref Value) del) const {
		foreach (i; 0 .. keys.length)
			if (keys[i] != nullKey)
				if (auto ret = del(values[i]))
					return ret;
		return 0;
	}

	int opApply(int delegate(in ref ushort, ref Value) del) {
		foreach (i; 0 .. keys.length)
			if (keys[i] != nullKey)
				if (auto ret = del(keys[i], values[i]))
					return ret;
		return 0;
	}

	int opApply(int delegate(in ref ushort, in ref Value) del) const {
		foreach (i; 0 .. keys.length)
			if (keys[i] != nullKey)
				if (auto ret = del(keys[i], values[i]))
					return ret;
		return 0;
	}

	void reserve(size_t amount) {
		auto newcap = ((length + amount) * 3) / 2;
		resize(newcap);
	}

	void shrink() {
		auto newcap = length * 3 / 2;
		resize(newcap);
	}

	private size_t findIndex(ushort key) const {
		if (length == 0) return size_t.max;
		size_t start = key & (keys.length-1);
		auto i = start;
		while (keys[i] != key) {
			if (keys[i] == nullKey) return size_t.max;
			if (++i >= keys.length) i -= keys.length;
			if (i == start) return size_t.max;
		}
		return i;
	}

	private size_t findInsertIndex(ushort key) const {
		size_t target = key & (keys.length-1);
		auto i = target;
		while (!keys[i] == nullKey && keys[i] != key) {
			if (++i >= keys.length) i -= keys.length;
			assert (i != target, "No free bucket found, HashMap full!?");
		}
		return i;
	}

	private void grow(size_t amount) {
		auto newsize = length + amount;
		if (newsize < (keys.length*2)/3) return;
		auto newcap = keys.length ? keys.length : 16;
		while (newsize >= (newcap*2)/3) newcap *= 2;
		resize(newcap);
	}

	private void resize(size_t newSize)
	{
		assert(!resizing);
		resizing = true;
		scope(exit) resizing = false;

		newSize = nextPOT(newSize);

		auto oldKeys = keys;
		auto oldValues = values;

		if (newSize) {
			void[] array = allocator.allocate((Key.sizeof + Value.sizeof) * newSize);
			keys = cast(Key[])(array[0..Key.sizeof * newSize]);
			values = cast(Value[])(array[Key.sizeof * newSize..$]);
			//infof("%s %s %s", array.length, keys.length, values.length);
			keys[] = nullKey;
			foreach (i, ref key; oldKeys) {
				if (key != nullKey) {
					auto idx = findInsertIndex(key);
					keys[idx] = key;
					values[idx] = oldValues[i];
				}
			}
		} else {
			keys = null;
			values = null;
		}

		if (oldKeys) {
			void[] arr = (cast(void[])oldKeys).ptr[0..(Key.sizeof + Value.sizeof) * newSize];
			allocator.deallocate(arr);
		}
	}
}
