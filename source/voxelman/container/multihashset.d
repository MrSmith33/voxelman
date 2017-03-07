/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.container.multihashset;

import voxelman.container.hashmap;

// Stores number of entries for each key
struct MultiHashSet(Key, Key nullKey = Key.max) {
	HashMap!(Key, size_t, nullKey) keys;

	size_t get(Key key) {
		return keys.get(key, 0);
	}

	alias opIndex = get;

	// returns true if key was first time added after this call
	bool add(Key key) {
		auto numEntries = keys.getOrCreate(key, 0);
		++(*numEntries);
		return (*numEntries) == 1; // new observer
	}

	// ditto
	bool add(Key key, size_t addedEntries) {
		auto numEntries = keys.getOrCreate(key, 0);
		(*numEntries) += addedEntries;
		return (*numEntries) == addedEntries; // new observer
	}

	// returns true if key was removed after this call
	bool remove(Key key) {
		auto numEntries = key in keys;
		if (numEntries) {
			--(*numEntries);
			if ((*numEntries) == 0) {
				keys.remove(key);
				return true;
			}
		}
		return false;
	}

	bool remove(Key key, size_t removedEntries) {
		auto numEntries = key in keys;
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
	int opApply(scope int delegate(Key) del) {
		foreach (Key key; keys.byKey())
			if (auto ret = del(key))
				return ret;
		return 0;
	}

	int opApply(scope int delegate(Key, size_t) del) {
		foreach (Key key, size_t numEntries; keys)
			if (auto ret = del(key, numEntries))
				return ret;
		return 0;
	}
}
