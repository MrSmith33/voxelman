/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.container.chunkedbuffer;

import voxelman.container.buffer;
import std.experimental.allocator.gc_allocator;
alias allocator = GCAllocator.instance;
import std.stdio;
import std.algorithm : min, equal, swap;
import voxelman.math : nextPOT, divCeil;

struct ChunkedBuffer(T, size_t pageSize = 4096)
{
	enum pageBytes = pageSize*T.sizeof;

	Buffer!(T*) chunkBuffer; // array of pages
	// Must be kept private since it can be used to check for avaliable space
	// when used as output range
	private size_t length;
	// can be non-zero after removeFront
	private size_t firstChunkDataPos;

	void put(T[] items ...)
	{
		reserve(items.length);

		size_t firstChunkIndex = length / pageSize;
		size_t firstChunkPos = length % pageSize;
		size_t firstChunkSpace = pageSize - firstChunkPos;
		T*[] chunks = chunkBuffer.data;

		length += items.length;

		size_t firstChunkItems = min(firstChunkSpace, items.length);
		auto firstChunk = chunks[firstChunkIndex];
		firstChunk[firstChunkPos..firstChunkPos+firstChunkItems] = items[0..firstChunkItems];
		items = items[firstChunkItems..$];

		size_t chunkIndex = firstChunkIndex + 1;
		while(items.length > 0)
		{
			size_t numItemsToWrite = min(pageSize, items.length);
			chunks[chunkIndex++][0..numItemsToWrite] = items[0..numItemsToWrite];
			items = items[numItemsToWrite..$];
		}
	}

	void put(R)(R itemRange)
	{
		foreach(item; itemRange)
			put(item);
	}

	alias putBack = put;

	void removeFront(size_t howMany = 1)
	{
		assert(howMany <= length);
		size_t newLength = length - howMany;
		size_t numFrontRemovedItems = firstChunkDataPos + howMany;
		size_t firstUsedChunk = numFrontRemovedItems / pageSize;
		firstChunkDataPos = numFrontRemovedItems % pageSize;
		size_t lastUsedChunk = (firstChunkDataPos + newLength) / pageSize + 1;
		T*[] chunks = chunkBuffer.data;
		size_t i;
		foreach (chunkIndex; firstUsedChunk..lastUsedChunk)
		{
			swap(chunks[i++], chunks[chunkIndex]);
		}
		length = newLength;
	}

	void removeBack(size_t howMany = 1)
	{
		assert(howMany <= length);
		length -= howMany;
	}

	void clear() nothrow
	{
		length = 0;
	}

	size_t capacity() const @property
	{
		return chunkBuffer.data.length * pageSize;
	}

	size_t reserved() const @property
	{
		return capacity - length;
	}

	void reserve(size_t items)
	{
		if (reserved < items)
		{
			// alloc chunks
			size_t numExtraChunks = divCeil(items, pageSize);
			chunkBuffer.reserve(numExtraChunks);

			foreach(_; 0..numExtraChunks)
			{
				chunkBuffer.put(cast(T*)allocator.allocate(pageBytes).ptr);
			}
		}
	}

	alias ChunkRange = ChunkedBufferChunks!(T, pageSize);
	alias ItemRange = ChunkedBufferItemRange!(T, pageSize);

	auto byChunk()
	{
		size_t numChunksWithData = divCeil(length, pageSize);
		return ChunkRange(chunkBuffer.data[0..numChunksWithData], length, firstChunkDataPos);
	}

	auto opSlice()
	{
		return ItemRange(chunkBuffer.data, length, firstChunkDataPos);
	}

	auto opSlice(size_t from, size_t to)
	{
		return ItemRange(chunkBuffer.data, length, firstChunkDataPos)[from..to];
	}
}

struct ChunkedBufferChunks(T, size_t pageSize)
{
	private T*[] chunks;
	size_t totalItems;
	T[] front;

	size_t length() { return chunks.length; }
	alias opDollar = length;

	bool empty() { return totalItems == 0; }

	this(T*[] chunks, size_t length, size_t firstChunkOffset)
	{
		totalItems = length;
		this.chunks = chunks;
		if (length)
		{
			size_t pageItems = min(totalItems, pageSize-firstChunkOffset);
			size_t end = firstChunkOffset + pageItems;
			front = chunks[0][firstChunkOffset..end];
		}
	}

	void popFront()
	{
		totalItems -= front.length;
		chunks = chunks[1..$];

		size_t pageItems = min(totalItems, pageSize);
		if (pageItems) front = chunks[0][0..pageItems];
	}
}

struct ChunkedBufferItemRange(T, size_t pageSize)
{
	private T*[] chunks;
	size_t length;
	private size_t firstChunkPos;

	alias opDollar = length;

	bool empty() { return length == 0; }

	T front() { return chunks[0][firstChunkPos]; }

	void popFront()
	{
		++firstChunkPos;
		if (firstChunkPos == pageSize)
		{
			chunks = chunks[1..$];
			firstChunkPos = 0;
		}
		--length;
	}

	auto opSlice(size_t from, size_t to)
	{
		assert(from < length);
		assert(to <= length);
		size_t startOffset = from + firstChunkPos;
		size_t firstChunk = startOffset / pageSize;
		size_t len = to - from;
		size_t endOffset = startOffset + len;
		size_t lastChunk = divCeil(endOffset, pageSize);
		return ChunkedBufferItemRange(
			chunks[firstChunk..lastChunk],
			len,
			startOffset % pageSize);
	}
}

unittest
{
	ChunkedBuffer!(int, 1) buf;
	buf.put(1, 2);
	assert(buf[].equal([1, 2]));
	assert(buf.byChunk.equal([[1], [2]]));
	assert(buf.length == 2);
	assert(buf.capacity == 2);
	assert(buf.reserved == 0);
}

unittest
{
	ChunkedBuffer!(int, 2) buf;
	buf.put(1, 2, 3, 4);
	assert(buf[].equal([1, 2, 3, 4]));
	assert(buf.byChunk.equal([[1, 2], [3, 4]]));
	assert(buf.byChunk.length == 2);
	assert(buf.length == 4);
	assert(buf.capacity == 4);
	assert(buf.reserved == 0);

	assert(buf[1..3].equal([2, 3]));

	buf.put(5);
	assert(buf[].equal([1, 2, 3, 4, 5]));
	assert(buf.byChunk.equal([[1, 2], [3, 4], [5]]));
	assert(buf.byChunk.length == 3);
	assert(buf.length == 5);
	assert(buf.capacity == 6);
	assert(buf.reserved == 1);
}

unittest
{
	ChunkedBuffer!(int, 2) buf;
	buf.put(1, 2, 3, 4);

	buf.removeBack(3);

	assert(buf[].equal([1]));
	assert(buf.byChunk.equal([[1]]));
	assert(buf.byChunk.length == 1);
	assert(buf.length == 1);
	assert(buf.capacity == 4);
	assert(buf.reserved == 3);
}

unittest
{
	ChunkedBuffer!(int, 2) buf;
	buf.put(1, 2, 3, 4);

	buf.removeFront(3);

	assert(buf[].equal([4]));
	assert(buf.byChunk.equal([[4]]));
	assert(buf.byChunk.length == 1);
	assert(buf.length == 1);
	assert(buf.capacity == 4);
	assert(buf.reserved == 3);
}

unittest
{
	import std.range;
	ChunkedBuffer!(int, 1) buf;
	buf.put(100.iota);

	buf.removeFront(10);
	buf.removeBack(10);

	assert(buf[].equal(iota(10, 90)));
	assert(buf.byChunk.length == 80);
	assert(buf.length == 80);
	assert(buf.capacity == 100);
	assert(buf.reserved == 20);
}
