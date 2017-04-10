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
