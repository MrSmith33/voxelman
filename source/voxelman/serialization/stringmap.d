/**
Copyright: Copyright (c) 2017-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.serialization.stringmap;

import voxelman.container.buffer;
import voxelman.serialization;

struct StringMap {
	Buffer!string array;
	uint[string] map;

	void load(string[] ids) {
		array.clear();
		foreach(str; ids) {
			put(str);
		}
	}

	string[] strings() {
		return array.data;
	}

	uint put(string key) {
		uint id = cast(uint)array.data.length;
		map[key] = id;
		array.put(key);
		return id;
	}

	uint get(ref IoKey key) {
		if (key.id == uint.max) {
			key.id = map.get(key.str, uint.max);
			if (key.id == uint.max) {
				key.id = put(key.str);
			}
		}
		return key.id;
	}
}
