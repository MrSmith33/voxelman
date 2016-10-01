/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.plugindata;

import std.experimental.logger;
import std.experimental.allocator.mallocator;
import std.array : empty;
import cbor;
import voxelman.world.worlddb : WorldDb;

struct PluginDataSaver
{
	enum DATA_BUF_SIZE = 1024*1024*2;
	enum KEY_BUF_SIZE = 1024*20;
	private ubyte[] dataBuf;
	private ubyte[] keyBuf;
	private size_t dataLen;
	private size_t keyLen;

	package(voxelman.world) void alloc() @nogc {
		dataBuf = cast(ubyte[])Mallocator.instance.allocate(DATA_BUF_SIZE);
		keyBuf = cast(ubyte[])Mallocator.instance.allocate(KEY_BUF_SIZE);
	}

	package(voxelman.world) void free() @nogc {
		Mallocator.instance.deallocate(dataBuf);
		Mallocator.instance.deallocate(keyBuf);
	}

	ubyte[] tempBuffer() @property @nogc {
		return dataBuf[dataLen..$];
	}

	void writeWorldEntry(string key, size_t bytesWritten) {
		keyLen += encodeCbor(keyBuf[keyLen..$], key);
		keyLen += encodeCbor(keyBuf[keyLen..$], bytesWritten);
		dataLen += bytesWritten;
	}

	//void writeDimensionEntry(string key, DimensionId dim, size_t bytesWritten) {
	//	keyLen += encodeCbor(keyBuf[keyLen..$], key);
	//	keyLen += encodeCbor(keyBuf[keyLen..$], bytesWritten);
	//	dataLen += bytesWritten;
	//}

	package(voxelman.world) void reset() @nogc {
		dataLen = 0;
		keyLen = 0;
	}

	package(voxelman.world) int opApply(int delegate(string key, ubyte[] data) dg)
	{
		ubyte[] keyEntriesData = keyBuf[0..keyLen];
		ubyte[] data = dataBuf;
		while(!keyEntriesData.empty)
		{
			auto key = decodeCborSingle!string(keyEntriesData);
			auto dataSize = decodeCborSingle!size_t(keyEntriesData);
			auto result = dg(key, data[0..dataSize]);
			data = data[dataSize..$];

			if (result) return result;
		}
		return 0;
	}
}

struct PluginDataLoader
{
	package(voxelman.world) WorldDb worldDb;

	ubyte[] readWorldEntry(string key) {
		ubyte[] data = worldDb.getPerWorldValue(key);
		//infof("Reading %s %s", key, data.length);
		//printCborStream(data[]);
		return data;
	}

	//ubyte[] readDimensionEntry(string key, DimensionId dim) {
	//	ubyte[] data = worldDb.getPerDimensionValue(key, dim);
	//	//infof("Reading %s %s", key, data.length);
	//	//printCborStream(data[]);
	//	return data;
	//}
}
