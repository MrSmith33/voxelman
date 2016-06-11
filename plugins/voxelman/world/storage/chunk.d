/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.chunk;

import std.experimental.logger;
import std.array : uninitializedArray;
import std.string : format;
import std.typecons : Nullable;

import dlib.math.vector;

import voxelman.core.config;
import voxelman.block.utils;
import voxelman.core.chunkmesh;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.utils;
import voxelman.world.storage.volume;
import voxelman.utils.compression;

enum FIRST_LAYER = 0;

BlockId[] allocBlockLayerArray() {
	return uninitializedArray!(BlockId[])(CHUNK_SIZE_CUBE);
}

void freeBlockLayerArray(BlockId[] buffer) {
	import core.memory : GC;
	GC.free(buffer.ptr);
}

struct ChunkHeaderItem {
	ChunkWorldPos cwp;
	uint numLayers;
	uint metadata; // for task purposes
}
static assert(ChunkHeaderItem.sizeof == 16);

struct ChunkLayerTimestampItem {
	uint timestamp;
	ubyte layerId;
}
static assert(ChunkLayerTimestampItem.sizeof == 8);

/// Stores layer of chunk data. Blocks are stored as array of blocks or uniform.
struct ChunkLayerItem
{
	StorageType type;
	ubyte layerId;
	ushort dataLength;
	uint timestamp;
	union {
		ulong uniformData;
		void* dataPtr; /// Stores ptr to the first byte of data. The length of data is in dataLength.
	}
	ushort metadata;
	this(StorageType _type, ubyte _layerId, ushort _dataLength, uint _timestamp, ulong _uniformData, ushort _metadata = 0) {
		type = _type; layerId = _layerId; dataLength = _dataLength; timestamp = _timestamp; uniformData = _uniformData; metadata = _metadata;
	}
	this(StorageType _type, ubyte _layerId, ushort _dataLength, uint _timestamp, ubyte* _dataPtr, ushort _metadata = 0) {
		type = _type; layerId = _layerId; dataLength = _dataLength; timestamp = _timestamp; dataPtr = _dataPtr; metadata = _metadata;
	}
	this(T)(StorageType _type, ubyte _layerId, uint _timestamp, T[] _array, ushort _metadata = 0) {
		type = _type; layerId = _layerId; dataLength = cast(ushort)_array.length; timestamp = _timestamp; dataPtr = cast(void*)_array.ptr; metadata = _metadata;
	}
	this(ChunkLayerSnap l, ubyte _layerId) {
		type = l.type;
		layerId = _layerId;
		dataLength = l.dataLength;
		timestamp = l.timestamp;
		uniformData = l.uniformData;
		metadata = l.metadata;
	}

	string toString() const
	{
		return format("ChunkLayerItem(%s, %s, %s, %s, {%s, %s}, %s)",
			type, layerId, dataLength, timestamp, uniformData, dataPtr, metadata);
	}
}
static assert(ChunkLayerItem.sizeof == 24);

struct WriteBuffer
{
	bool isUniform = true;
	bool isModified = true;
	union {
		BlockId[] blocks;
		BlockId uniformBlockId;
	}
	ushort metadata;

	void makeUniform(BlockId blockId, ushort _metadata = 0) {
		if (!isUniform) {
			freeBlockLayerArray(blocks);
			isUniform = true;
		}
		uniformBlockId = blockId;
		metadata = _metadata;
	}

	// Allocates buffer and copies layer data.
	void makeArray(Layer)(Layer layer) {
		if (isUniform) {
			blocks = allocBlockLayerArray();
			isUniform = false;
		}
		layer.copyToBuffer(blocks); // uncompresses automatically
		metadata = layer.metadata;
	}

	void copyFromLayer(Layer)(Layer layer) {
		if (layer.type == StorageType.uniform) {
			makeUniform(layer.getUniform!BlockId(), layer.metadata);
		} else {
			makeArray(layer);
		}
	}
}

/// Container for chunk updates
/// If blockChanges is null uses newBlockData
struct ChunkChange
{
	uvec3 a, b; // volume
	BlockId blockId;
}

// container of single block change.
// position is chunk local [0; CHUNK_SIZE-1];
struct BlockChange
{
	ushort index;
	BlockId blockId;
}

ushort[2] areaOfImpact(BlockChange[] changes)
{
	ushort start;
	ushort end;

	foreach(change; changes)
	{
		if (change.index < start)
			start = change.index;
		if (change.index > end)
			end = change.index;
	}

	return cast(ushort[2])[start, end+1];
}

// stores all used snapshots of the chunk.
struct BlockDataSnapshot
{
	BlockData blockData;
	TimestampType timestamp;
	uint numUsers;
}

enum StorageType : ubyte
{
	uniform,
	//linearMap,
	//hashMap,
	compressedArray,
	fullArray,
}

/// Stores layer of chunk data. Blocks are stored as array of blocks or uniform.
struct ChunkLayerSnap
{
	union {
		ulong uniformData;
		void* dataPtr; /// Stores ptr to the first byte of data. The length of data is in dataLength.
	}
	ushort dataLength; // unused when uniform
	ushort numUsers;
	ushort metadata;
	StorageType type;
	uint timestamp;
	this(StorageType _type, ushort _dataLength, uint _timestamp, ulong _uniformData, ushort _metadata = 0) {
		type = _type; dataLength = _dataLength; timestamp = _timestamp; uniformData = _uniformData; metadata = _metadata;
	}
	this(StorageType _type, ushort _dataLength, uint _timestamp, void* _dataPtr, ushort _metadata = 0) {
		type = _type; dataLength = _dataLength; timestamp = _timestamp; dataPtr = _dataPtr; metadata = _metadata;
	}
	this(T)(StorageType _type, uint _timestamp, T[] _array, ushort _metadata = 0) {
		type = _type; dataLength = cast(ushort)_array.length; timestamp = _timestamp; dataPtr = _array.ptr; metadata = _metadata;
	}
	this(ChunkLayerItem l) {
		numUsers = 0;
		timestamp = l.timestamp;
		type = l.type;
		dataLength = l.dataLength;
		uniformData = l.uniformData;
		metadata = l.metadata;
	}
}

enum isSomeLayer(Layer) = is(Layer == ChunkLayerSnap) || is(Layer == ChunkLayerItem) || is(Layer == Nullable!ChunkLayerSnap);

T[] getArray(T, Layer)(const ref Layer layer)
	if (isSomeLayer!Layer)
{
	assert(layer.type != StorageType.uniform);
	return (cast(T*)layer.dataPtr)[0..layer.dataLength];
}
T getUniform(T, Layer)(const ref Layer layer)
	if (isSomeLayer!Layer)
{
	return cast(T)layer.uniformData;
}

BlockId getBlockId(Layer)(const ref Layer layer, BlockChunkIndex index)
	if (isSomeLayer!Layer)
{
	if (layer.type == StorageType.uniform) return layer.getUniform!BlockId;
	if (layer.type == StorageType.compressedArray) {
		BlockId[CHUNK_SIZE_CUBE] buffer;
		uncompressIntoBuffer(layer, buffer);
		return buffer[index];
	}
	return getArray!BlockId(layer)[index];
}

BlockId getBlockId(Layer)(const ref Layer layer, int x, int y, int z)
	if (isSomeLayer!Layer)
{
	return getBlockId(layer, BlockChunkIndex(x, y, z));
}

bool isUniform(Layer)(const ref Layer layer) @property
	if (isSomeLayer!Layer)
{
	return layer.type == StorageType.uniform;
}

BlockData toBlockData(Layer)(const ref Layer layer)
	if (isSomeLayer!Layer)
{
	BlockData res;
	res.uniform = layer.type == StorageType.uniform;
	res.metadata = layer.metadata;
	if (!res.uniform)
		res.blocks = layer.getArray!BlockId();
	else
		res.uniformType = layer.getUniform!BlockId;
	return res;
}

ChunkLayerItem fromBlockData(const ref BlockData bd)
{
	if (bd.uniform)
		return ChunkLayerItem(StorageType.uniform, FIRST_LAYER, 0, 0, bd.uniformType, bd.metadata);
	else
		return ChunkLayerItem(StorageType.fullArray, FIRST_LAYER, 0, bd.blocks, bd.metadata);
}

void copyToBuffer(Layer)(Layer layer, BlockId[] outBuffer)
	if (isSomeLayer!Layer)
{
	assert(outBuffer.length == CHUNK_SIZE_CUBE);
	if (layer.type == StorageType.uniform)
		outBuffer[] = cast(BlockId)layer.uniformData;
	else if (layer.type == StorageType.fullArray)
		outBuffer[] = layer.getArray!BlockId;
	else if (layer.type == StorageType.compressedArray)
		uncompressIntoBuffer(layer, outBuffer);
}

size_t getLayerDataBytes(Layer)(const ref Layer layer)
	if (isSomeLayer!Layer)
{
	if (layer.type == StorageType.fullArray)
		return layer.getArray!BlockId.length * BlockId.sizeof;
	else if (layer.type == StorageType.compressedArray)
		return layer.getArray!ubyte.length;
	return 0;
}

size_t getLayerDataBytes(WriteBuffer* writeBuffer)
{
	if (!writeBuffer.isUniform) {
		return writeBuffer.blocks.length * BlockId.sizeof;
	}
	return 0;
}

void applyChanges(WriteBuffer* writeBuffer, BlockChange[] changes)
{
	assert(!writeBuffer.isUniform);
	foreach(change; changes)
	{
		writeBuffer.blocks[change.index] = change.blockId;
	}
}

void applyChanges(WriteBuffer* writeBuffer, ChunkChange[] changes)
{
	assert(!writeBuffer.isUniform);
	foreach(change; changes)
	{
		setSubArray(writeBuffer.blocks, Volume(ivec3(change.a), ivec3(change.b)), change.blockId);
	}
}

void setSubArray(BlockId[] buffer, Volume volume, BlockId blockId)
{
	assert(buffer.length == CHUNK_SIZE_CUBE);

	if (volume.position.x == 0 && volume.size.x == CHUNK_SIZE)
	{
		if (volume.position.z == 0 && volume.size.z == CHUNK_SIZE)
		{
			if (volume.position.y == 0 && volume.size.y == CHUNK_SIZE)
			{
				buffer[] = blockId;
			}
			else
			{
				auto from = volume.position.y * CHUNK_SIZE_SQR;
				auto to = (volume.position.y + volume.size.y) * CHUNK_SIZE_SQR;
				buffer[from..to] = blockId;
			}
		}
		else
		{
			foreach(y; volume.position.y..(volume.position.y + volume.size.y))
			{
				auto from = y * CHUNK_SIZE_SQR + volume.position.z * CHUNK_SIZE;
				auto to = y * CHUNK_SIZE_SQR + (volume.position.z + volume.size.z) * CHUNK_SIZE;
				buffer[from..to] = blockId;
			}
		}
	}
	else
	{
		int posx = volume.position.x;
		int endx = volume.position.x + volume.size.x;
		int endy = volume.position.y + volume.size.y;
		int endz = volume.position.z + volume.size.z;
		foreach(y; volume.position.y..endy)
		foreach(z; volume.position.z..endz)
		{
			auto offset = y * CHUNK_SIZE_SQR + z * CHUNK_SIZE;
			auto from = posx + offset;
			auto to = endx + offset;
			buffer[from..to] = blockId;
		}
	}
}

void uncompressIntoBuffer(Layer)(Layer layer, BlockId[] outBuffer)
{
	assert(outBuffer.length == CHUNK_SIZE_CUBE);
	BlockId[] blocks = decompress(layer.getArray!ubyte, outBuffer);
	assert(blocks.length == CHUNK_SIZE_CUBE);
}

// Stores blocks of the chunk.
struct BlockData
{
	void validate()
	{
		if (!uniform && blocks.length != CHUNK_SIZE_CUBE) {
			fatalf("Size of uniform chunk != CHUNK_SIZE_CUBE, == %s", blocks.length);
		}
	}

	/// null if uniform is true, or contains chunk data otherwise
	BlockId[] blocks;

	/// type of common block
	BlockId uniformType = 0; // Unknown block

	/// is chunk filled with block of the same type
	bool uniform = true;

	ushort metadata;
}
