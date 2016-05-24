/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.utils.hashset;

struct HashSet(K) {
	private void[0][K] set;

	void put()(auto ref K key) {
		set[key] = (void[0]).init;
	}

	bool remove()(auto ref K key) {
		return set.remove(key);
	}

	size_t length() const @property {
		return set.length;
	}

	@property bool empty() const {
		return set.length == 0;
	}

	bool opCast(T: bool)() const {
		return !empty;
	}

	bool opBinaryRight(string op)(auto ref K key) const if(op == "in") {
		return cast(bool)(key in set);
	}

	void clear() {
		set = null;
	}

	auto items() @property {
		return set.byKey;
	}
}
