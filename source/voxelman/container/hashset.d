/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.container.hashset;

deprecated struct HashSet(Key) {
	private void[0][Key] set;

	void put()(auto ref Key key) {
		set[key] = (void[0]).init;
	}

	bool remove()(auto ref Key key) {
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

	bool opBinaryRight(string op)(auto ref Key key) const if(op == "in") {
		return cast(bool)(key in set);
	}

	void clear() {
		set = null;
	}

	int opApply(scope int delegate(Key) del) {
		foreach (key; set.byKey)
			if (auto ret = del(key))
				return ret;
		return 0;
	}
}
