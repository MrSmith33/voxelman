/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.container.intkeyhashset;

import voxelman.math : nextPOT;

struct IntKeyHashSet(Key, Key nullKey = Key.max)
{
	import std.experimental.allocator.gc_allocator;
	import std.experimental.allocator.mallocator;

	Key[] keys;
	size_t length;

	private bool resizing;

	//alias allocator = Mallocator.instance;
	alias allocator = GCAllocator.instance;

	this(ubyte[] array, size_t length) {
		keys = cast(Key[])array;
		this.length = length;
	}

	ubyte[] getTable() {
		return cast(ubyte[])keys;
	}

	@property size_t capacity() const { return keys.length; }
	@property bool empty() const { return length == 0; }

	bool remove(Key key) {
		auto idx = findIndex(key);
		if (idx == size_t.max) return false;
		auto i = idx;
		while (true)
		{
			keys[i] = nullKey;

			size_t j = i, r;
			do {
				if (++i >= keys.length) i -= keys.length;
				if (keys[i] == nullKey)
				{
					--length;
					return true;
				}
				r = keys[i] & (keys.length-1);
			}
			while ((j<r && r<=i) || (i<j && j<r) || (r<=i && i<j));
			keys[j] = keys[i];
		}
	}

	void clear() {
		keys[] = nullKey;
		length = 0;
	}

	void put(Key key) {
		grow(1);
		auto i = findInsertIndex(key);
		if (keys[i] != key) ++length;

		keys[i] = key;
	}

	bool opIndex(Key key) inout {
		auto idx = findIndex(key);
		return idx != size_t.max;
	}

	bool opBinaryRight(string op)(Key key) inout if (op == "in") {
		auto idx = findIndex(key);
		return idx != size_t.max;
	}

	int opApply(scope int delegate(Key) del) {
		foreach (i; 0 .. keys.length)
			if (keys[i] != nullKey)
				if (auto ret = del(keys[i]))
					return ret;
		return 0;
	}

	void reserve(size_t amount) {
		auto newcap = ((length + amount) * 3) / 2;
		resize(newcap);
	}

	void shrink() {
		auto newcap = length * 3 / 2;
		resize(newcap);
	}

	private size_t findIndex(Key key) const {
		if (length == 0) return size_t.max;
		size_t start = key & (keys.length-1);
		auto i = start;
		while (keys[i] != key) {
			if (keys[i] == nullKey) return size_t.max;
			if (++i >= keys.length) i -= keys.length;
			if (i == start) return size_t.max;
		}
		return i;
	}

	private size_t findInsertIndex(Key key) const {
		size_t target = key & (keys.length-1);
		auto i = target;
		while (keys[i] != nullKey && keys[i] != key) {
			if (++i >= keys.length) i -= keys.length;
			assert (i != target, "No free bucket found, HashMap full!?");
		}
		return i;
	}

	private void grow(size_t amount) {
		auto newsize = length + amount;
		if (newsize < (keys.length*2)/3) return;
		auto newcap = keys.length ? keys.length : 1;
		while (newsize >= (newcap*2)/3) newcap *= 2;
		resize(newcap);
	}

	private void resize(size_t newSize)
	{
		assert(!resizing);
		resizing = true;
		scope(exit) resizing = false;

		newSize = nextPOT(newSize);

		auto oldKeys = keys;

		if (newSize) {
			void[] array = allocator.allocate(Key.sizeof * newSize);
			keys = cast(Key[])array;
			keys[] = nullKey;
			foreach (i, ref key; oldKeys) {
				if (key != nullKey) {
					auto idx = findInsertIndex(key);
					keys[idx] = key;
				}
			}
		} else {
			keys = null;
		}

		if (oldKeys) {
			void[] arr = cast(void[])oldKeys;
			allocator.deallocate(arr);
		}
	}

	void toString()(scope void delegate(const(char)[]) sink)
	{
		import std.format : formattedWrite;
		sink.formattedWrite("[",);
		foreach(key; this)
		{
			sink.formattedWrite("%s, ", key);
		}
		sink.formattedWrite("]");
	}
}
