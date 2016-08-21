/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.container.cache;

// entries are sorted based on last access time.
// successfull gets bring entries to the front of list,
// thus preventing them from being replaces on put
struct Cache(Key, Value, uint maxEntries)
{
	enum lastEntryIndex = maxEntries - 1;

	// returns null if key is not found.
	// gives entry max priority
	Value* get(Key key)
	{
		static bool searchPred(Entry a, Key b)
		{
			return a.key == b;
		}
		import std.algorithm : countUntil;
		ptrdiff_t entry = countUntil!searchPred(entries[0..numUsed], key);

		if (entry == -1)
			return null;
		else
		{
			bringEntryToFront(entry);
			return &values[entries[0].valueIndex];
		}
	}

	private void bringEntryToFront(size_t index)
	{
		Entry temp = entries[index];
		for(ptrdiff_t i = index-1; i>=0; --i)
		{
			entries[i+1] = entries[i];
		}
		entries[0] = temp;
	}

	void put(Key key, Value val)
	{
		Value* valPtr = put(key);
		*valPtr = val;
	}

	Value* put(Key key)
	{
		if (numUsed == maxEntries)
		{
			auto index = entries[lastEntryIndex].valueIndex;
			entries[lastEntryIndex] = Entry(key, index);
			bringEntryToFront(lastEntryIndex);
			return &values[index];
		}
		else
		{
			entries[numUsed] = Entry(key, numUsed);
			auto res = &values[numUsed];
			bringEntryToFront(numUsed);
			++numUsed;
			return res;
		}
	}

	void toString()(scope void delegate(const(char)[]) sink) const
	{
		import std.format : formattedWrite;
		sink.formattedWrite("Cache!(%s, %s, %s)(", Key, Value, maxEntries);
		foreach(i; 0..numUsed)
		{
			auto e = entries[i];
			sink.formattedWrite("%s:%s, ", e.key, values[e.valueIndex]);
		}
		sink.formattedWrite(")");
	}

	static struct Entry
	{
		Key key;
		size_t valueIndex;
	}

	Entry[maxEntries] entries;
	Value[maxEntries] values;
	size_t numUsed;
}

unittest
{
	Cache!(int, string, 3) cache;

	//cache.writeln;
	cache.put(1, "1");
	//cache.writeln;
	cache.put(2, "2");
	//cache.writeln;
	cache.put(3, "3");
	//cache.writeln;
	cache.put(4, "4");
	//cache.writeln;
	assert(cache.get(1) is null);

	assert(*cache.get(4) == "4");
	//cache.writeln;

	assert(cache.get(5) is null);

	cache.put(5, "5");
	//cache.writeln;
	assert(cache.get(2) is null);

	cache.get(3);
	//cache.writeln;
	assert(cache.entries[0].key == 3);
}
