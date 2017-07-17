/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.serialization.dataloader;

import std.traits : TemplateOf;
import voxelman.serialization;
import voxelman.utils.mapping;

struct PluginDataLoader
{
	StringMap* stringMap;
	ubyte[] delegate(ref IoKey) readEntryRaw;

	IoStorageType storageType() { return IoStorageType.database; }

	/// decodes entry if data in db is not empty. Leaves value untouched otherwise.
	void readEntryDecoded(T)(ref IoKey key, ref T value) {
		ubyte[] data = readEntryRaw(key);
		if (data)
			decodeCbor!(Yes.Duplicate)(data, value);
	}

	T readEntryDecoded(T)(ref IoKey key) {
		ubyte[] data = readEntryRaw(key);
		T value;
		if (data) {
			decodeCbor!(Yes.Duplicate)(data, value);
		}
		return value;
	}

	void readMapping(T)(ref IoKey key, ref T mapping)
		if (__traits(isSame, TemplateOf!T, Mapping))
	{
		ubyte[] data = readEntryRaw(key);
		if (data)
		{
			string[] value;
			decodeCbor!(Yes.Duplicate)(data, value);

			mapping.setMapping(value);
		}
	}
}
