/**
Copyright: Copyright (c) 2016-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.container.multihashset;

import voxelman.log;
import voxelman.container.hash.map;

/// Stores number of entries for each key
struct MultiHashSet(Key, Key emptyKey, Key deletedKey)
{
	mixin MultiHashSetImpl!(Key, HashMap!(Key, size_t, emptyKey, deletedKey));
}

/// ditto
struct MultiHashSet(Key)
{
	mixin MultiHashSetImpl!(Key, HashMap!(Key, size_t));
}

private mixin template MultiHashSetImpl(Key, HashMapT) {
	HashMapT keys;

	size_t get(Key key) {
		return keys.get(key, 0);
	}

	alias opIndex = get;

	// returns true if key was first time added after this call
	bool add(Key key, size_t addedEntries = 1) {
		size_t* numEntries = keys.getOrCreate(key, 0);
		(*numEntries) += addedEntries;
		return (*numEntries) == addedEntries; // new observer
	}

	// returns true if key was removed after this call
	bool remove(Key key, size_t removedEntries = 1) {
		size_t* numEntries = key in keys;
		if (numEntries) {
			size_t numToRemove = (*numEntries) >= removedEntries ? removedEntries : (*numEntries);
			(*numEntries) -= numToRemove;
			if ((*numEntries) == 0) {
				keys.remove(key);
				return true;
			}
		}
		return false;
	}

	// iterate over all keys
	int opApply(scope int delegate(in Key) del) {
		foreach (Key key; keys.byKey())
			if (auto ret = del(key))
				return ret;
		return 0;
	}

	int opApply(scope int delegate(in Key, size_t) del) {
		foreach (key, numEntries; keys)
			if (auto ret = del(key, numEntries))
				return ret;
		return 0;
	}
}

unittest {
	import std.stdio;
	MultiHashSet!int multiset;

	enum iter = 64;
	foreach (i; 0..iter) {
		foreach (j; 0..iter) {
			multiset.add(j);
			assert(multiset[j] == i+1);
		}
	}

	foreach (i; 0..iter) {
		foreach (j; 0..iter) {
			multiset.remove(j);
			assert(multiset[j] == iter-i-1);
		}
	}

	foreach (i; 0..iter) {
		foreach (j; 0..iter) {
			multiset.add(j);
			assert(multiset[j] == i+1);
		}
	}
}
