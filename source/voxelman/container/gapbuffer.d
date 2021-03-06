/**
Copyright: Copyright (c) 2017-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.container.gapbuffer;

import std.algorithm : max, equal;
import std.math : abs;
import std.stdio;
import std.experimental.allocator.gc_allocator;
alias allocator = GCAllocator.instance;
import voxelman.math : nextPOT;
import voxelman.container.chunkedrange;

struct GapBuffer(T)
{
	private T* buffer;
	size_t length;
	alias opDollar = length;
	private size_t gapLength;
	private size_t gapStart;

	private size_t secondChunkLength() const { return length - gapStart; }
	private size_t secondChunkStart() { return gapStart + gapLength; }
	private size_t capacity() { return gapLength + length; }
	private alias gapEnd = secondChunkStart;

	void putAt(size_t index, const T[] items ...)
	{
		reserve(items.length);
		moveGapTo(index);

		assert(index+items.length <= capacity);
		buffer[index..index+items.length] = items;
		length += items.length;
		gapStart += items.length;
		gapLength -= items.length;
		//printStructure();
	}

	void put(const T[] items ...) { putAt(length, items); }
	alias putBack = put;
	void putFront(const T[] items ...) { putAt(0, items); }

	void remove(size_t from, size_t itemsToRemove)
	{
		assert(from + itemsToRemove <= capacity);
		moveGapTo(from);
		length -= itemsToRemove;
		gapLength += itemsToRemove;
	}
	void removeFront(size_t itemsToRemove = 1) { remove(0, itemsToRemove); }
	void removeBack(size_t itemsToRemove = 1) { remove(length-itemsToRemove, itemsToRemove); }

	void reserve(size_t items)
	{
		assert(cast(ptrdiff_t)(length - gapStart) >= 0); // invariant
		if (gapLength < items)
		{
			import core.memory;
			GC.removeRange(buffer);
			size_t newCapacity = nextPOT(capacity + items);
			void[] tmp = buffer[0..capacity];
			allocator.reallocate(tmp, newCapacity*T.sizeof);
			buffer = cast(T*)tmp.ptr;
			moveItems(secondChunkStart, newCapacity-secondChunkLength, secondChunkLength);
			gapLength = newCapacity - length;
			GC.addRange(buffer, capacity * T.sizeof, typeid(T));
		}
	}

	void clear() nothrow
	{
		gapLength = capacity;
		length = 0;
		gapStart = 0;
	}

	ref T front() { return this[0]; }
	ref T back() { return this[$-1]; }

	ref T opIndex(size_t at)
	{
		assert(at < length);
		immutable size_t index = at < gapStart ? at : at + gapLength;
		return buffer[index];
	}

	auto opSlice()
	{
		return GapBufferSlice!T(&this, 0, length);
	}

	auto opSlice(size_t from, size_t to)
	{
		return this[][from..to];
	}

	T[] getContinuousSlice(size_t from, size_t to)
	{
		moveGapTo(to);
		return buffer[from..to];
	}

	private void moveItems(size_t from, size_t to, size_t length)
	{
		//writefln("  moveItems %s -> %s %s", from, to, length);
		if ( (to == from) || (length == 0) ) return;

		if (from > to)
		{
			while(length > 0)
			{
				buffer[to++] = buffer[from++];
				--length;
			}
		}
		else
		{
			from += length;
			to += length;

			while(length > 0)
			{
				buffer[--to] = buffer[--from];
				--length;
			}
		}
	}

	private void moveGapTo(size_t newGapPos)
	{
		//writefln("moveGapTo %s -> %s %s", gapStart, newGapPos, gapLength);
		//printStructure();
		if (newGapPos < gapStart)
		{
			immutable size_t itemsToMove = gapStart - newGapPos;
			moveItems(newGapPos, gapEnd - itemsToMove, itemsToMove);
			gapStart = newGapPos;
		}
		else if (newGapPos > gapStart)
		{
			immutable size_t itemsToMove = newGapPos - gapStart;
			moveItems(secondChunkStart, gapStart, itemsToMove);
			gapStart = newGapPos;
		}
		//printStructure();
	}

	private void printStructure()
	{
		writefln("  >%s|%s|%s", gapStart, gapLength, secondChunkLength);
		writefln("  >%(%s, %) | %(%s, %) | %(%s, %)", buffer[0..gapStart], buffer[gapStart..gapEnd], buffer[gapEnd..capacity]);
	}

	int opApply(scope int delegate(ref T) dg)
	{
		int result = 0;
		foreach(ref v; buffer[0..gapStart])
			if (dg(v)) break;
		foreach(ref v; buffer[gapEnd..capacity])
			if (dg(v)) break;
		return result;
	}

	int opApply(scope int delegate(size_t, ref T) dg)
	{
		int result = 0;
		size_t index;
		foreach(ref v; buffer[0..gapStart])
			if (dg(index++, v)) break;
		foreach(ref v; buffer[gapEnd..capacity])
			if (dg(index++, v)) break;
		return result;
	}
}

struct GapBufferSlice(T)
{
	private GapBuffer!T* buf;
	size_t start;
	size_t length;
	alias opDollar = length;

	bool empty() { return length == 0; }
	ref T front() { return (*buf)[start]; }
	ref T back() { return (*buf)[start+length-1]; }
	void popFront() { ++start; --length; }
	void popBack() { --length; }
	auto save() { return this; }
	ref T opIndex(size_t at) { return (*buf)[start + at]; }

	auto opSlice(size_t from, size_t to)
	{
		assert(from <= length, "From must be less than length");
		assert(to <= length);
		assert(from <= to);
		immutable size_t len = to - from;
		return GapBufferSlice(buf, start+from, len);
	}

	ChunkedRange!T toChunkedRange()
	{
		size_t end = start + length;
		if (start < buf.gapStart)
		{
			if (end >= buf.gapStart)
			{
				// slice contains the gap
				T[] first = buf.buffer[start..buf.gapStart];
				T* secondPtr = &buf.buffer[buf.gapEnd];
				size_t secondLength = length - (buf.gapStart-start);
				return ChunkedRange!T(first, secondLength, secondPtr, null, &GapBufferSlice_popFront!T);
			}
			else
			{
				// slice if before gap
				T[] first = buf.buffer[start..end];
				return ChunkedRange!T(first, 0, null, null, &GapBufferSlice_popFront!T);
			}
		}
		else
		{
			// slice if after gap
			size_t from = start + buf.gapLength;
			size_t to = from + length;
			T[] first = buf.buffer[from..to];
			return ChunkedRange!T(first, 0, null, null, &GapBufferSlice_popFront!T);
		}
	}
}

private static void GapBufferSlice_popFront(T)(
	ref T[] front,
	ref size_t secondLength,
	ref void* secondPtr,
	ref void* unused)
{
	front = (cast(T*)secondPtr)[0..secondLength];
	secondPtr = null;
	secondLength = 0;
}

unittest
{
	GapBuffer!char buf;

	buf.put("ab");
	buf.remove(1, 1);
	assert(buf[].equal("a"));
	assert(buf.length == 1);
}

unittest
{
	GapBuffer!int buf;
	assert(buf.length == 0);
	assert(buf.gapStart == 0);
	assert(buf.secondChunkLength == 0);

	buf.put(1, 2, 3, 4);
	assert(buf.length == 4);
	assert(buf[].equal([1, 2, 3, 4]));

	buf.putAt(2, 7, 8);
	assert(buf.length == 6);
	assert(buf[].equal([1, 2, 7, 8, 3, 4]));

	buf.remove(2, 2);
	assert(buf.length == 4);
	assert(buf[].equal([1, 2, 3, 4]));

	buf.remove(0, 4);
	assert(buf.length == 0);
	assert(buf[].equal((int[]).init));
}

unittest
{
	GapBuffer!int buf;
	buf.putFront(1, 2, 3, 4);
	//writefln("%s\n", buf[]);

	buf.putFront(1, 2, 3, 4);
	//writefln("%s\n", buf[]);

	buf.putFront(1, 2, 3, 4);
	//writefln("%s\n", buf[]);

	buf.putFront(1, 2, 3, 4);
	//writefln("%s\n", buf[]);

	assert(buf[].equal([
		1, 2, 3, 4,
		1, 2, 3, 4,
		1, 2, 3, 4,
		1, 2, 3, 4,
		]));

	buf.clear;
	assert(buf.length == 0);
}
