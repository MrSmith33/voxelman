/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.serialization.datasaver;

import std.traits : TemplateOf;
import std.array : empty;
import voxelman.container.buffer;
import voxelman.serialization;
import voxelman.utils.mapping;

struct PluginDataSaver
{
	StringMap* stringMap;
	ubyte[16] delegate(uint) getKey;
	private Buffer!ubyte buffer;
	private size_t prevDataLength;

	Buffer!ubyte* beginWrite() {
		prevDataLength = buffer.data.length;
		return &buffer;
	}

	IoStorageType storageType() { return IoStorageType.database; }

	void endWrite(ref IoKey key) {
		// write empty entries, they will be deleted in storage worker
		uint entrySize = cast(uint)(buffer.data.length - prevDataLength);
		buffer.put(*cast(ubyte[4]*)&entrySize);
		buffer.put(getKey(stringMap.get(key)));
	}

	void writeEntryEncoded(T)(ref IoKey key, T data) {
		beginWrite();
		encodeCbor(buffer, data);
		endWrite(key);
	}

	void writeMapping(T)(ref IoKey key, T mapping)
		if (__traits(isSame, TemplateOf!T, Mapping))
	{
		auto sink = beginWrite();
		encodeCborArrayHeader(sink, mapping.infoArray.length);
		foreach(const ref info; mapping.infoArray)
		{
			encodeCborString(sink, info.name);
		}
		endWrite(key);
	}

	void reset() @nogc {
		buffer.clear();
	}

	int opApply(scope int delegate(ubyte[16] key, ubyte[] data) dg)
	{
		ubyte[] data = buffer.data;
		while(!data.empty)
		{
			ubyte[16] key = data[$-16..$];
			uint entrySize = *cast(uint*)(data[$-4-16..$-16].ptr);
			ubyte[] entry = data[$-4-16-entrySize..$-4-16];
			auto result = dg(key, entry);

			data = data[0..$-4-16-entrySize];

			if (result) return result;
		}
		return 0;
	}
}

unittest
{
	ubyte[16] keyProducer(uint key) {
		return (ubyte[16]).init;
	}
	StringMap stringMap;
	auto saver = PluginDataSaver(&stringMap, &keyProducer);
	//StringMap stringMap;
	//saver.stringMap = &stringMap;

	auto dbKey1 = IoKey("Key1");
	saver.writeEntryEncoded(dbKey1, 1);

	auto dbKey2 = IoKey("Key2");
	auto sink = saver.beginWrite();
		encodeCbor(sink, 2);
	saver.endWrite(dbKey2);

	// iteration
	foreach(ubyte[16] key, ubyte[] data; saver) {
		//
	}
	saver.reset();
}
