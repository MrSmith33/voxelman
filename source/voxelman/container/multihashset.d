/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.container.multihashset;

import voxelman.container.hashmap;

// Stores number of entries for each key
struct MultiHashSet(Key) {
	HashMap!(Key, size_t) keys;

	size_t get(Key key) {
		return keys.get(key, 0);
	}

	// returns true if key was first time added after this call
	bool add(Key key) {
		auto numEntries = keys.getOrCreate(key, 0);
		++(*numEntries);
		return (*numEntries) == 1; // new observer
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

	// iterate over all keys
	int opApply(scope int delegate(Key) del) {
		foreach (Key key; keys)
			if (auto ret = del(key))
				return ret;
		return 0;
	}
}
