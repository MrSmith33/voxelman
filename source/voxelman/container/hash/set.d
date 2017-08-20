/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.container.hash.set;

import std.experimental.allocator.gc_allocator;
import voxelman.container.hash.hashtableparts;
import voxelman.container.hash.keybucket;

struct HashSet(Key, Key emptyKey, Key deletedKey, Alloc = GCAllocator)
{
	mixin HashTablePart!(KeyBucket!(Key, emptyKey, deletedKey), false);
}

struct HashSet(Key, Alloc = GCAllocator)
{
	mixin HashTablePart!(MetaKeyBucket!(Key), false);
}

unittest {
	void test(M)()
	{
		M map;
		map.put(2); // placed in bucket 0
		map.reserve(1); // capacity 2 -> 4, must be placed in bucket 2
		assert(map[2]);
	}

	test!(HashSet!(ushort, ushort.max, ushort.max-1));
	test!(HashSet!(ushort));
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
			map.put(key);
		}

		foreach (i, ushort key; keys) {
			assert(map.length == keys.length - i);
			map.remove(key);
		}

		foreach (i, ushort key; keys) {
			assert(map.length == i);
			map.put(key);
		}
	}

	import std.stdio;

	test!(HashSet!(ushort, ushort.max, ushort.max-1));
	test!(HashSet!(ushort));
}
