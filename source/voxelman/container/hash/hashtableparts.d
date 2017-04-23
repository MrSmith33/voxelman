/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.container.hash.hashtableparts;

//version = DEBUG_TRACE;
//version = DEBUG_INVARIANT;

/// If store_values = false then table works like hashset
mixin template HashTablePart(KeyBucketT, bool store_values)
{
	size_t length; // num of used buckets
	size_t occupiedBuckets; // num of used + deleted buckets
	size_t capacity; // array length
	KeyBucketT* keyBuckets;
	version(DEBUG_TRACE) void* debugId;

	alias allocator = Alloc.instance;

	static if (store_values)
	{
		enum Bucket_size = KeyBucketT.sizeof + Value.sizeof;
		mixin HashMapImpl;
	}
	else
	{
		enum Bucket_size = KeyBucketT.sizeof;
		mixin HashSetImpl;
	}

	pragma(inline, true)
	private static size_t getHash(Key key) {
		import std.traits : isIntegral;
		static if (isIntegral!Key)
			return cast(size_t)key;
		else
			return hashOf(key);
	}

	@property bool empty() const { return length == 0; }

	/// Returns false if no value was deleted, true otherwise
	bool remove(Key key)
	{
		auto index = findIndex(key);
		if (index == size_t.max) return false;
		removeAtIndex(index);
		version(DEBUG_TRACE) tracef("[%s] remove %s at %s cap %s len %s", debugId, key, index, capacity, length);
		return true;
	}

	void clear() {
		KeyBucketT.clearBuckets(keyBuckets[0..capacity]);
		occupiedBuckets = length = 0;
		version(DEBUG_INVARIANT) checkUsed();
	}

	void reserve(size_t amount)
	{
		import std.stdio;
		import voxelman.math : nextPOT;

		// check current bucket array for free space (including deleted items)
		auto requiredCapacity = (occupiedBuckets + amount) * 2;
		if (requiredCapacity <= capacity) return;

		// calculate required capacity without deleted items (since we allocate new array)
		auto newRequiredCapacity = (length + amount) * 2;
		auto newCapacity = nextPOT(newRequiredCapacity);
		resize(newCapacity);
	}

	private void removeAtIndex(size_t index)
	{
		keyBuckets[index].markAsDeleted();
		--length;
		version(DEBUG_INVARIANT) checkUsed();
		// TODO mark as empty if empty to the right
    }

	import std.stdio;
	import voxelman.log;
	private size_t findIndex(Key key) const
	{
		if (length == 0) return size_t.max;
		auto index = getHash(key) & (capacity - 1);
		version(DEBUG_TRACE) tracef("[%s] find %s at %s cap %s len %s", debugId, key, index, capacity, length);
		while (true) {
			if (keyBuckets[index].key == key && keyBuckets[index].used)
			{
				version(DEBUG_TRACE) tracef("* U @%s key %s", index, keyBuckets[index].key);
				return index;
			}

			// we will find empty key eventually since we don't allow full hashmap
			if (keyBuckets[index].empty)
			{
				version(DEBUG_TRACE) tracef("* E @%s key %s", index, keyBuckets[index].key);
				return size_t.max;
			}
			index = (index + 1) & (capacity - 1);
		}
	}

	private size_t findInsertIndex(Key key) const
	{
		size_t index = getHash(key) & (capacity - 1);
		version(DEBUG_TRACE) tracef("[%s] insert %s at %s cap %s", debugId, key, index, capacity);
		while (keyBuckets[index].used && keyBuckets[index].key != key)
		{
			version(DEBUG_TRACE) {
				if (keyBuckets[index].used)
					tracef("  U @%s key %s", index, keyBuckets[index].key);
				else if (keyBuckets[index].deleted)
					tracef("  D @%s key %s", index, keyBuckets[index].key);
			}
			index = (index + 1) & (capacity - 1);
		}
		version(DEBUG_TRACE) {
			if (keyBuckets[index].empty)
				tracef("* E @%s key %s", index, keyBuckets[index].key);
			else if (keyBuckets[index].used) {
				tracef("* U @%s key %s", index, keyBuckets[index].key);
			} else {
				tracef("* D @%s key %s", index, keyBuckets[index].key);
			}
		}
		return index;
	}

	private void resize(size_t newCapacity)
	{
		import std.experimental.allocator;
		import std.random;

		version(DEBUG_TRACE) {
			if (capacity == 0) {
				debugId = cast(void*)uniform(0, ushort.max);
			}
		}

		auto oldKeyBuckets = keyBuckets;
		static if (store_values) {
			auto oldValues = values[0..capacity];
		}

		auto oldCapacity = capacity;

		// findInsertIndex below uses new capacity
		capacity = newCapacity;
		occupiedBuckets = length;

		if (newCapacity)
		{
			void[] array = allocator.allocate(Bucket_size * newCapacity);
			setStorageArray(array, newCapacity);
			keyBuckets[0..newCapacity] = KeyBucketT.init;

			version(DEBUG_TRACE) tracef("[%s] resize from %s to %s, len %s", debugId, oldCapacity, newCapacity, length);
			foreach (i, ref bucket; oldKeyBuckets[0..oldCapacity])
			{
				if (bucket.used)
				{
					auto index = findInsertIndex(bucket.key);
					keyBuckets[index] = bucket;
					version(DEBUG_TRACE) tracef("  move %s, %s -> %s", bucket.key, i, index);
					static if (store_values) values[index] = oldValues[i];
				}
			}
		}
		else
		{
			keyBuckets = null;
			static if (store_values) values = null;
		}

		if (oldKeyBuckets) {
			void[] arr = (cast(void*)oldKeyBuckets)[0..Bucket_size * oldCapacity];
			allocator.deallocate(arr);
		}
	}

	void[] getStorage() {
		return (cast(void*)keyBuckets)[0..Bucket_size * capacity];
	}

	/// data must be allocated with allocator of this object
	void setStorage(void[] data, size_t length, size_t occupiedBuckets) {
		this.length = length;
		this.capacity = data.length / Bucket_size;
		this.occupiedBuckets = occupiedBuckets;
		setStorageArray(data, capacity);
		version(DEBUG_INVARIANT) checkUsed();
	}

	private void setStorageArray(void[] data, size_t capacity) {
		keyBuckets = cast(KeyBucketT*)(data.ptr);
		static if (store_values)
			values = cast(Value*)(data.ptr + capacity*KeyBucketT.sizeof);
	}

	private void checkUsed() {
		import std.string;
		auto used = calcUsed();
		assert(used == length, format("%s != %s", used, length));
	}

	private size_t calcUsed() {
		size_t totalUsed;
		foreach (bucket; keyBuckets[0..capacity])
			totalUsed += bucket.used;
		return totalUsed;
	}
}

mixin template HashMapImpl()
{
	import std.stdio;
	import std.string;
	Value* values;

	alias KeyT = Key;
	alias ValueT = Value;

	/// Removes value via pointer returned by getOrCreate or opIn
	/// Prevents extra lookup
	void removeByPtr(Value* value) {
		auto idx = indexFromPtr(value);
		if (idx == size_t.max) return;
		removeAtIndex(idx);
	}

	alias put = tryAssignValue;

	void opIndexAssign(Value value, Key key)
	{
		tryAssignValue(key, value);
	}

	import voxelman.log;
	private Value* assignValue(Key key, Value value)
	{
		size_t index = findInsertIndex(key);
		if (keyBuckets[index].empty) {
			++occupiedBuckets;
			++length;
		}
		else if (keyBuckets[index].deleted) {
			++length;
		}
		else {
			assert(keyBuckets[index].key == key);
			assert(keyBuckets[index].used);
		}
		keyBuckets[index].assignKey(key);
		values[index] = value;
		version(DEBUG_INVARIANT) checkUsed();
		version(DEBUG_TRACE) tracef("[%s] = %s at %s, length %s", key, value, index, length);
		return &values[index];
	}

	private size_t indexFromPtr(Value* value) {
		auto offset = value - values;
		if (offset > capacity || offset < 0) return size_t.max;
		return cast(size_t)offset;
	}

	inout(Value)* opBinaryRight(string op)(Key key) inout if (op == "in")
	{
		auto index = findIndex(key);
		//tracef("in index %s", index);
		if (index == size_t.max) return null;
		return &values[index];
	}

	ref inout(Value) opIndex(Key key) inout
	{
		import std.exception : enforce;
		auto index = findIndex(key);
		enforce(index != size_t.max, "Non-existing key access");
		return values[index];
	}

	Value get(Key key, Value default_value = Value.init)
	{
		auto index = findIndex(key);
		//tracef("get %s index %s len %s", key, index, length);
		if (index == size_t.max) return default_value;
		return values[index];
	}

	Value* getOrCreate(Key key, Value default_value = Value.init)
	{
		auto index = findIndex(key);
		//tracef("getOrCreate index %s", index);
		if (index == size_t.max) return tryAssignValue(key, default_value);
		return &values[index];
	}

	Value* getOrCreate(Key key, out bool wasCreated, Value default_value = Value.init)
	{
		auto index = findIndex(key);

		if (index == size_t.max)
		{
			wasCreated = true;
			return tryAssignValue(key, default_value);
		}

		return &values[index];
	}

	private Value* tryAssignValue(Key key, Value value)
	{
		if ((capacity >> 2) > occupiedBuckets)
		{
			return assignValue(key, value);
		}
		else
		{
			reserve(1);
			return assignValue(key, value);
		}
	}

	int opApply(scope int delegate(ref Value) del) {
		foreach (i, ref bucket; keyBuckets[0..capacity])
			if (bucket.used)
				if (auto ret = del(values[i]))
					return ret;
		return 0;
	}

	int opApply(scope int delegate(in Key, ref Value) del) {
		foreach (i, ref bucket; keyBuckets[0..capacity])
			if (bucket.used)
				if (auto ret = del(bucket.key, values[i]))
					return ret;
		return 0;
	}

	auto byKey() {
		alias HM_TYPE = typeof(this);
		static struct ByKey {
			HM_TYPE* hashmap;
			int opApply(scope int delegate(Key) del) {
				foreach (bucket; hashmap.keyBuckets[0..hashmap.capacity])
					if (bucket.used)
						if (auto ret = del(bucket.key))
							return ret;
				return 0;
			}
		}
		return ByKey(&this);
	}

	void printBuckets() {
		size_t totalUsed;
		foreach (index, bucket; keyBuckets[0..capacity])
		{
			if (bucket.empty)
				writefln("E %s %s", bucket.key, values[index]);
			else if (bucket.used) {
				++totalUsed;
				writefln("U %s %s", bucket.key, values[index]);
			}
			else if (bucket.deleted)
				writefln("D %s %s", bucket.key, values[index]);
		}
		writefln("totalUsed %s length %s", totalUsed, length);
	}

	void toString()(scope void delegate(const(char)[]) sink)
	{
		import std.format : formattedWrite;
		sink.formattedWrite("[",);
		foreach(key, value; this)
		{
			sink.formattedWrite("%s:%s, ", key, value);
		}
		sink.formattedWrite("]");
	}
}

mixin template HashSetImpl()
{
	void put(Key key)
	{
		if ((capacity >> 2) > occupiedBuckets)
		{
			putKey(key);
		}
		else
		{
			reserve(1);
			putKey(key);
		}
	}

	private void putKey(Key key)
	{
		size_t index = findInsertIndex(key);
		if (keyBuckets[index].empty) {
			++occupiedBuckets;
			++length;
		}
		else if (keyBuckets[index].deleted) {
			++length;
		}
		else {
			assert(keyBuckets[index].key == key);
			assert(keyBuckets[index].used);
		}
		keyBuckets[index].assignKey(key);
		version(DEBUG_INVARIANT) checkUsed();
	}

	bool opBinaryRight(string op)(Key key) const if(op == "in") {
		auto index = findIndex(key);
		return index != size_t.max;
	}

	bool opIndex(Key key) inout
	{
		auto index = findIndex(key);
		return index != size_t.max;
	}

	int opApply(scope int delegate(in Key) del) const {
		foreach (ref bucket; keyBuckets[0..capacity])
			if (bucket.used)
				if (auto ret = del(bucket.key))
					return ret;
		return 0;
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
