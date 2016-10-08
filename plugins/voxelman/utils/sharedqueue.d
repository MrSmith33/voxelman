/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

// Based on Martin Nowak's lock-free package.
module voxelman.utils.sharedqueue;

import core.atomic;
import core.thread : Thread;
import std.experimental.allocator.mallocator;
import voxelman.log;

//version = DBG_QUEUE;
private enum PAGE_SIZE = 4096;
/// Single-producer single-consumer fixed size circular buffer queue.
shared struct SharedQueue {
	size_t capacity;

	void alloc(string debugName = null, size_t _capacity = roundPow2(PAGE_SIZE)) shared {
		_debugName = debugName;
		capacity = _capacity;
		assert(capacity > 0, "Cannot have a capacity of 0.");
		assert(roundPow2(capacity) == capacity, "The capacity must be a power of 2");
		_data = cast(shared ubyte[])Mallocator.instance.allocate(capacity);
		assert(_data, "Cannot allocate memory for queue");
	}

	void free() shared {
		Mallocator.instance.deallocate(cast(ubyte[])_data);
	}

	@property bool empty() shared const {
		return !length;
	}

	@property size_t length() shared const {
		return atomicLoad!(MemoryOrder.acq)(_writePos) - atomicLoad!(MemoryOrder.acq)(_readPos);
	}

	@property size_t space() shared const {
		return capacity - length;
	}

	@property bool full() shared const {
		return length == capacity;
	}

	void pushItem(I)(I item) shared {
		immutable writePosition = atomicLoad!(MemoryOrder.acq)(_writePos);
		// space < I.sizeof
		while (capacity - writePosition + atomicLoad!(MemoryOrder.acq)(_readPos) < I.sizeof) {
			yield();
		}
		setItem(item, writePosition);
		atomicStore!(MemoryOrder.rel)(_writePos, writePosition + I.sizeof);
		version(DBG_QUEUE) printTrace!"pushItem"(item);
	}

	I popItem(I)() shared {
		//static assert(I.sizeof <= capacity, "Item size is greater then capacity");

		immutable pos = atomicLoad!(MemoryOrder.acq)(_readPos);
		I res;
		getItem(res, pos);
		atomicStore!(MemoryOrder.rel)(_readPos, pos + I.sizeof);
		version(DBG_QUEUE) printTrace!"popItem"(res);
		return res;
	}

	void popItem(I)(out I item) shared {
		//static assert(I.sizeof <= capacity, "Item size is greater then capacity");

		immutable pos = atomicLoad!(MemoryOrder.acq)(_readPos);
		getItem(item, pos);
		atomicStore!(MemoryOrder.rel)(_readPos, pos + I.sizeof);
		version(DBG_QUEUE) printTrace!"popItem"(item);
	}

	I peekItem(I)() shared {
		//static assert(I.sizeof <= capacity, "Item size is greater then capacity");

		immutable pos = atomicLoad!(MemoryOrder.acq)(_readPos);
		I res;
		getItem(res, pos);
		version(DBG_QUEUE) printTrace!"peekItem"(res);
		return res;
	}

	void peekItem(I)(out I item) shared {
		//static assert(I.sizeof <= capacity, "Item size is greater then capacity");

		immutable pos = atomicLoad!(MemoryOrder.acq)(_readPos);
		getItem(item, pos);
		version(DBG_QUEUE) printTrace!"peekItem"(item);
	}

	void dropItem(I)() shared {
		//static assert(I.sizeof <= capacity, "Item size is greater then capacity");

		immutable pos = atomicLoad!(MemoryOrder.acq)(_readPos);
		atomicStore!(MemoryOrder.rel)(_readPos, pos + I.sizeof);
		version(DBG_QUEUE) printTrace!"dropItem"();
	}

	private void getItem(I)(out I item, const size_t at) shared const {
		//static assert(I.sizeof <= capacity, "Item size is greater then capacity");
		ubyte[] itemData = (*cast(ubyte[I.sizeof]*)&item);

		size_t start = at & (capacity - 1);
		size_t end = (at + I.sizeof) & (capacity - 1);
		if (end > start)
		{
			//             item[0] v          v item[$]
			//         ...........|...item...|..........
			// data[0] ^     start ^          ^ end     ^ data[$]
			itemData[0..$] = _data[start..end];
		}
		else
		{
			//                 item[$] v       item[0] v
			//          |...itemEnd...|...............|...itemStart...|
			//  _data[0] ^         end ^         start ^               ^ _data[$]
			size_t firstPart = I.sizeof - end;
			itemData[0..firstPart] = _data[start..$];
			itemData[firstPart..$] = _data[0..end];
		}
	}

	void setItem(I)(auto const ref I item, const size_t at) shared {
		//static assert(I.sizeof <= capacity, "Item size is greater then capacity");
		ubyte[] itemData = (*cast(ubyte[I.sizeof]*)&item);

		size_t start = at & (capacity - 1);
		size_t end = (at + I.sizeof) & (capacity - 1);
		if (end > start)
		{
			//             item[0] v          v item[$]
			//         ...........|...item...|..........
			// data[0] ^     start ^          ^ end     ^ data[$]
			_data[start..end] = itemData[0..$];
		}
		else
		{
			//               item[$] v       item[0] v
			//        |...itemEnd...|...............|...itemStart...|
			// data[0] ^         end ^         start ^       data[$] ^
			size_t firstPart = I.sizeof - end;
			_data[start..$] = itemData[0..firstPart];
			_data[0..end] = itemData[firstPart..$];
		}
		atomicFence();
	}

	// enter multipart message mode
	void startMessage() shared {
		_msgWritePos = atomicLoad!(MemoryOrder.acq)(_writePos);
		version(DBG_QUEUE) printTrace!"startMessage"();
	}

	// exit multipart message mode
	void endMessage() shared {
		atomicStore!(MemoryOrder.rel)(_writePos, _msgWritePos);
		version(DBG_QUEUE) printTrace!"endMessage"();
	}

	// skip to fill in later with setItem in multipart message mode
	size_t skipMessageItem(I)() shared {
		//static assert(I.sizeof <= capacity, "Item size is greater then capacity");
		size_t skippedItemPos = cast(size_t)_msgWritePos;
		// space < I.sizeof
		while (capacity - _msgWritePos + atomicLoad!(MemoryOrder.acq)(_readPos) < I.sizeof) {
			yield();
		}
		cast(size_t)_msgWritePos += I.sizeof;
		version(DBG_QUEUE) printTrace!"skipMessageItem"();
		return skippedItemPos;
	}

	// can cause dead-lock if consumer is waiting for producer.
	// Make sure that there is enough space. Or else keep consuming
	// push in multipart message mode
	void pushMessagePart(I)(auto const ref I item) shared {
		//static assert(I.sizeof <= capacity, "Item size is greater then capacity");
		// space < I.sizeof
		while (capacity - _msgWritePos + atomicLoad!(MemoryOrder.acq)(_readPos) < I.sizeof) {
			yield();
		}
		setItem(item, _msgWritePos);
		cast(size_t)_msgWritePos += I.sizeof;
		version(DBG_QUEUE) printTrace!"pushMessagePart"(item);
	}

	static void yield() {
		Thread.yield();
		//infof("yield");
	}

private:
	size_t _msgWritePos;
	size_t _writePos;
	size_t _readPos;
	ubyte[] _data;
	string _debugName;

	import std.concurrency : thisTid;
	void printTrace(string funname, D)(D data) {
		version(DBG_QUEUE) tracef("%s.%s."~funname~"(%s)\n\tmwp %s, wp %s, rp %s\n",
			thisTid, _debugName, data, _msgWritePos, cast(size_t)_writePos, cast(size_t)_readPos);
	}
	void printTrace(string funname)() {
		version(DBG_QUEUE) tracef("%s.%s."~funname~"()\n\tmwp %s, wp %s, rp %s\n",
			thisTid, _debugName, _msgWritePos, cast(size_t)_writePos, cast(size_t)_readPos);
	}
}

size_t roundPow2(size_t v) {
	import core.bitop : bsr;
	return v ? cast(size_t)1 << bsr(v) : 0;
}
