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
import voxelman.utils.compression;

enum FIRST_LAYER = 0;

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

/// Container for chunk updates
/// If blockChanges is null uses newBlockData
struct ChunkChange
{
	BlockChange[] blockChanges;
	BlockData newBlockData;
}

// container of single block change.
// position is chunk local [0; CHUNK_SIZE-1];
struct BlockChange
{
	// index of block in chunk data
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
	if (layer.type == StorageType.uniform) return cast(BlockId)layer.uniformData;
	return getArray!BlockId(layer)[index];
}

BlockId getBlockId(Layer)(const ref Layer layer, int x, int y, int z)
	if (isSomeLayer!Layer)
{
	if (layer.type == StorageType.uniform) return cast(BlockId)layer.uniformData;
	return getArray!BlockId(layer)[BlockChunkIndex(x, y, z)];
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

void applyChanges(BlockId[] writeBuffer, BlockChange[] changes)
{
	assert(writeBuffer.length == CHUNK_SIZE_CUBE);
	foreach(change; changes)
	{
		writeBuffer[BlockChunkIndex(change.index)] = change.blockId;
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
