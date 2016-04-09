/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.storage.chunk;

import std.experimental.logger;
import std.array : uninitializedArray;
import std.string : format;
import std.typecons : Nullable;

import dlib.math.vector;

import voxelman.core.config;
import voxelman.block.utils;
import voxelman.core.chunkmesh;
import voxelman.storage.coordinates;
import voxelman.storage.region;
import voxelman.storage.utils;
import voxelman.utils.compression;

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
		type = _type; layerId = _layerId; dataLength = cast(ushort)_array.length; timestamp = _timestamp; dataPtr = _array.ptr; metadata = _metadata;
	}
	this(ChunkLayerSnap l, ubyte _layerId) {
		type = l.type;
		layerId = _layerId;
		dataLength = l.dataLength;
		timestamp = l.timestamp;
		uniformData = l.uniformData;
		metadata = l.metadata;
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
	BlockId getBlockType(BlockChunkIndex index)
	{
		if (type == StorageType.uniform) return cast(BlockId)uniformData;
		return getArray!BlockId(this)[index];
	}
}

enum isSomeLayer(Layer) = is(Layer == ChunkLayerSnap) || is(Layer == ChunkLayerItem) || is(Layer == Nullable!ChunkLayerSnap);

T[] getArray(T, Layer)(Layer layer)
	if (isSomeLayer!Layer)
{
	assert(layer.type != StorageType.uniform);
	return (cast(T*)layer.dataPtr)[0..layer.dataLength];
}
T getUniform(T, Layer)(Layer layer)
	if (isSomeLayer!Layer)
{
	return cast(T)layer.uniformData;
}

BlockData toBlockData(Layer)(Layer layer)
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

void copyToBuffer(ChunkLayerSnap snap, BlockId[] outBuffer)
{
	assert(outBuffer.length == CHUNK_SIZE_CUBE);
	if (snap.type == StorageType.uniform)
		outBuffer[] = cast(BlockId)snap.uniformData;
	else if (snap.type == StorageType.fullArray)
		outBuffer[] = snap.getArray!BlockId;
	else if (snap.type == StorageType.compressedArray)
		uncompressIntoBuffer(snap, outBuffer);
}

void uncompressIntoBuffer(ChunkLayerSnap snap, BlockId[] outBuffer)
{
	assert(outBuffer.length == CHUNK_SIZE_CUBE);
	BlockId[] blocks = decompress(snap.getArray!BlockId, outBuffer);
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

	void convertToArray()
	{
		if (uniform)
		{
			blocks = uninitializedArray!(BlockId[])(CHUNK_SIZE_CUBE);
			blocks[] = uniformType;
			uniform = false;
		}
	}

	void copyToBuffer(BlockId[] outBuffer)
	{
		assert(outBuffer.length == CHUNK_SIZE_CUBE);
		if (uniform)
			outBuffer[] = uniformType;
		else
			outBuffer[] = blocks;
	}

	void convertToUniform(BlockId _uniformType)
	{
		uniform = true;
		uniformType = _uniformType;
		deleteBlocks();
	}

	void deleteBlocks()
	{
		blocks = null;
	}

	BlockId getBlockType(BlockChunkIndex index)
	{
		if (uniform) return uniformType;
		return blocks[index];
	}

	// returns true if data was changed
	bool setBlockType(BlockChunkIndex index, BlockId blockId)
	{
		if (uniform)
		{
			if (uniformType != blockId)
			{
				convertToArray();
				blocks[index] = blockId;
				return true;
			}
		}
		else
		{
			if (blocks[index] == blockId)
				return false;

			blocks[index] = blockId;
			return true;
		}

		return false;
	}

	// returns [first changed index, last changed index + 1]
	// if they match, then no changes occured
	// for use on client, when handling MultiblockChangePacket
	ushort[2] applyChanges(BlockChange[] changes)
	{
		ushort start;
		ushort end;

		foreach(change; changes)
		{
			if (setBlockType(BlockChunkIndex(change.index), change.blockId))
			{
				if (change.index < start)
					start = change.index;
				if (change.index > end)
					end = change.index;
			}
		}

		return cast(ushort[2])[start, end+1];
	}

	// Same as applyChanges, but does only
	// change application, no area of impact is calculated
	void applyChangesFast(BlockChange[] changes)
	{
		foreach(change; changes)
		{
			setBlockType(BlockChunkIndex(change.index), change.blockId);
		}
	}

	//
	void applyChangesChecked(BlockChange[] changes)
	{
		foreach(change; changes)
		{
			if (change.index <= CHUNK_SIZE_CUBE)
				setBlockType(BlockChunkIndex(change.index), change.blockId);
		}
	}
}

// Single chunk.
// Used in client only.
// To be replaced by layers.
struct Chunk
{
	@disable this();

	this(ChunkWorldPos position)
	{
		this.position = position;
	}

	BlockId getBlockType(int x, int y, int z)
	{
		return getBlockType(BlockChunkIndex(x, y, z));
	}

	BlockId getBlockType(BlockChunkIndex blockChunkIndex)
	{
		return snapshot.blockData.getBlockType(blockChunkIndex);
	}

	bool allAdjacentLoaded() @property
	{
		foreach(a; adjacent)
		{
			if (a is null || !a.isLoaded) return false;
		}

		return true;
	}

	bool canBeMeshed() @property
	{
		return isLoaded && allAdjacentLoaded;
	}

	bool needsMesh() @property
	{
		return isLoaded && isVisible && !hasMesh && !isMeshing;
	}

	bool isUsed() @property
	{
		return numReaders > 0 || hasWriter;
	}

	bool adjacentUsed() @property
	{
		foreach(a; adjacent)
			if (a !is null && a.isUsed) return true;
		return false;
	}

	bool adjacentHasUnappliedChanges() @property
	{
		foreach(a; adjacent)
			if (a !is null && a.hasUnappliedChanges) return true;
		return false;
	}

	bool isMarkedForDeletion() @property
	{
		return next || prev;
	}

	BlockDataSnapshot* getReadableSnapshot(TimestampType timestamp)
	{
		if (isLoaded)
			return &snapshot;
		else
			return null;
	}

	BlockDataSnapshot* getWriteableSnapshot(TimestampType timestamp)
	{
		if (isLoaded)
		{
			snapshot.timestamp = timestamp;
			return &snapshot;
		}
		else
			return null;
	}

	ChunkWorldPos position;
	BlockDataSnapshot snapshot;
	ChunkMesh mesh;
	Chunk*[6] adjacent;

	// updates
	ChunkChange change;
	ubyte[] newMeshData; // used for swapping

	bool isLoaded = false;
	bool isVisible = false;
	bool hasMesh = false;
	bool isMeshing = false;


	// If marked, then chunk is awaiting remesh.
	// Do not add chunk to mesh if already dirty
	bool isDirty = false;

	// Used when remeshing.
	// true if chunk is in changedChunks queue and has unapplied changes
	bool hasUnappliedChanges = false;

	// How many tasks are reading or writing this chunk
	bool hasWriter = false;
	ushort numReaders = 0;

	// In deletion queue.
	Chunk* next;
	Chunk* prev;
}
