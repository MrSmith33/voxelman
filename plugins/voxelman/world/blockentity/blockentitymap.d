/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.blockentity.blockentitymap;

import voxelman.container.hash.map;
import std.experimental.allocator.mallocator;
import voxelman.world.storage.chunk.layer;

alias BlockEntityMap = HashMap!(ushort, ulong, ushort.max, ushort.max-1, BlockEntityMapAllocator);

void setLayerMap(Layer)(ref Layer layer, BlockEntityMap map) {
	void[] arr = map.getStorage();

	void* dataPtr = arr.ptr - ExtraMapData.sizeof;
	size_t dataLength = arr.length + ExtraMapData.sizeof;

	auto extraMapData = cast(ExtraMapData*)dataPtr;
	extraMapData.length = cast(ushort)map.length;
	extraMapData.occupiedBuckets = cast(ushort)map.occupiedBuckets;

	layer.dataPtr = dataPtr;
	layer.dataLength = cast(LayerDataLenType)dataLength;
}

BlockEntityMap getHashMapFromLayer(Layer)(const ref Layer layer) {
	BlockEntityMap result;

	if (layer.type == StorageType.fullArray)
	{
		ubyte[] data = layer.getArray!ubyte;
		auto extraMapData = cast(ExtraMapData*)data.ptr;

		void[] mapData = data[ExtraMapData.sizeof..$];

		result.setStorage(mapData, extraMapData.length, extraMapData.occupiedBuckets);
	} else if (layer.type == StorageType.compressedArray) {
		assert(false, "Cannot get map from compressed chunk layer");
	}

	return result;
}

struct ExtraMapData
{
	ushort length;
	ushort occupiedBuckets;
}

struct BlockEntityMapAllocator
{
	@trusted @nogc nothrow
	void[] allocate(size_t bytes) shared
	{
		void[] buffer = Mallocator.instance.allocate(bytes + ExtraMapData.sizeof);
		return buffer[ExtraMapData.sizeof..$];
	}

	@system @nogc nothrow
	bool deallocate(void[] b) shared
	{
		void* ptr = b.ptr-ExtraMapData.sizeof;
		Mallocator.instance.deallocate(ptr[0..b.length + ExtraMapData.sizeof]);
		return true;
	}

	static shared BlockEntityMapAllocator instance;
}
