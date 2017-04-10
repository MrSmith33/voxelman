/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.container.buffer;

import std.experimental.allocator.gc_allocator;
alias allocator = GCAllocator.instance;
import voxelman.math : nextPOT;


struct Buffer(T)
{
	T[] buf;
	private size_t length;

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

	T[] data() {
		return buf[0..length];
	}

	void clear() nothrow {
		length = 0;
	}

	size_t capacity() @property {
		return buf.length - length;
	}

	void reserve(size_t items)
	{
		if (buf.length - length < items)
		{
			size_t newCapacity = nextPOT(buf.length + items);
			void[] tmp = buf;
			allocator.reallocate(tmp, newCapacity*T.sizeof);
			buf = cast(T[])tmp;
		}
	}
}
