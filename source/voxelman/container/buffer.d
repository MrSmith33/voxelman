/**
Copyright: Copyright (c) 2016-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.container.buffer;

import voxelman.math : nextPOT;

struct Buffer(T)
{
	T[] buf;
	// Must be kept private since it can be used to check for avaliable space
	// when used as output range
	private size_t length;

	bool empty() { return length == 0; }

	void put(T[] items ...)
	{
		reserve(items.length);
		buf[length..length+items.length] = items;
		length += items.length;
	}

	void put(R)(R itemRange)
	{
		foreach(item; itemRange)
			put(item);
	}

	void stealthPut(T item)
	{
		reserve(1);
		buf[length] = item;
	}

	/// Increases length and returns void-initialized slice to be filled by user
	T[] voidPut(size_t howMany)
	{
		reserve(howMany);
		length += howMany;
		return buf[length-howMany..length];
	}

	ref T opIndex(size_t at)
	{
		return buf[at];
	}

	ref T back() { return buf[length-1]; }

	inout(T[]) data() inout {
		return buf[0..length];
	}

	void clear() nothrow {
		length = 0;
	}

	size_t capacity() const @property {
		return buf.length;
	}

	void reserve(size_t items)
	{
		if (buf.length - length < items)
		{
			size_t newCapacity = nextPOT(buf.length + items);
			buf.length = newCapacity;
		}
	}

	void unput(size_t numItems)
	{
		length -= numItems;
	}
}
