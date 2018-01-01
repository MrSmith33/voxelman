/**
Copyright: Copyright (c) 2017-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.container.chunkedrange;

struct ChunkedRange(T)
{
	T[] front;
	bool empty() { return front.length == 0; }
	size_t joinedLength() { return front.length + itemsLeft; }
	void popFront() { popFrontHandler(front, itemsLeft, data0, data1); }

	size_t itemsLeft;
	void* data0;
	void* data1;
	void function(ref T[], ref size_t, ref void*, ref void*) popFrontHandler;
	auto byItem() { return ByItem!T(this); }

	void copyInto(T[] sink)
	{
		assert(sink.length >= joinedLength);
		foreach(chunk; this)
		{
			sink[0..chunk.length] = chunk;
			sink = sink[chunk.length..$];
		}
	}
}

struct ByItem(T)
{
	private ChunkedRange!T range;
	bool empty() { return range.empty; }
	size_t length() { return range.joinedLength; }
	alias opDollar = length;
	T front() { return range.front[0]; }
	void popFront() {
		range.front = range.front[1..$];
		if (range.front.length == 0) range.popFront;
	}
	void copyInto(T[] sink) { range.copyInto(sink); }
}
