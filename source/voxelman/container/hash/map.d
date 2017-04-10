/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.container.hash.map;

import std.experimental.allocator.gc_allocator;
import voxelman.container.hash.hashtableparts;
import voxelman.container.hash.keybucket;

struct HashMap(Key, Value, Alloc = GCAllocator)
{
	mixin HashTablePart!(MetaKeyBucket!(Key), true);
}

struct HashMap(Key, Value, Key emptyKey, Key deletedKey, Alloc = GCAllocator)
{
	mixin HashTablePart!(KeyBucket!(Key, emptyKey, deletedKey), true);
}

unittest {
	import std.string;
	void test(M)()
	{
		M map;
		ushort[] keys = [140,268,396,524,652,780,908,28,156,284,
			412,540,668,796,924,920,792,664,536,408,280,152,24];
		foreach (i, ushort key; keys) {
			//writefln("set1 %s %s", map, map.length);
			map[key] = key;
			//writefln("set2 %s %s", map, map.length);
			assert(map.length == i+1, format("length %s != %s", i+1, map.length));
			assert(key in map && map[key] == key, format("key in map %s %s", key in map, map[key]));
			assert(map.get(key, 0) == key);
		}
	}

	test!(HashMap!(ushort, ulong, ushort.max, ushort.max-1));
	test!(HashMap!(ushort, ulong));
}

unittest {
	void test(M)()
	{
		M map;
		map[2] = 10; // placed in bucket 0
		map.reserve(1); // capacity 2 -> 4, must be placed in bucket 2
		assert(map[2] == 10);
	}

	test!(HashMap!(ushort, ulong, ushort.max, ushort.max-1));
	test!(HashMap!(ushort, ulong));
}

unittest {
	import std.string;
	void test(M)()
	{
		M map;
		ushort[] keys = [140,268,396,524,652,780,908,28,156,284,
			412,540,668,796,924,920,792,664,536,408,280,152,24];

		foreach (i, ushort key; keys) {
			assert(map.length == i);
			map[key] = key;
		}

		foreach (i, ushort key; keys) {
			assert(map.length == keys.length - i);
			map.remove(key);
		}

		foreach (i, ushort key; keys) {
			assert(map.length == i);
			map[key] = key;
		}
	}

	test!(HashMap!(ushort, ulong, ushort.max, ushort.max-1));
	test!(HashMap!(ushort, ulong));
}
