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
import std.experimental.logger;

private enum PAGE_SIZE = 4096;
/// Single-producer single-consumer fixed size circular buffer queue.
shared struct SharedQueue(T, size_t _capacity = roundPow2!(PAGE_SIZE / T.sizeof)) {
	enum capacity = _capacity;
	static assert(capacity > 0, "Cannot have a capacity of 0.");
	static assert(roundPow2!capacity == capacity, "The capacity must be a power of 2");
	static assert(T.sizeof <= 8, "Cannot atomically use provided type");

	void alloc() shared {
		_data = cast(shared T[])Mallocator.instance.allocate(capacity * T.sizeof);
		assert(_data, "Cannot allocate memory for queue");
	}

	void free() shared {
		Mallocator.instance.deallocate(cast(ubyte[])_data);
	}

	@property bool empty() shared const {
		return !length;
	}

	@property size_t length() shared const {
		return atomicLoad!(MemoryOrder.acq)(_wpos) - atomicLoad!(MemoryOrder.acq)(_rpos);
	}

	@property size_t space() shared const {
		return capacity - length;
	}

	@property bool full() shared const {
		return length == capacity;
	}

	void pushSingleItem(I)(I item) shared {
		while (full)
			yield();
		immutable pos = atomicLoad!(MemoryOrder.acq)(_wpos);
		pushItem(item);
		atomicStore!(MemoryOrder.rel)(_wpos, pos + 1);
	}

	I popItem(I)() shared {
		static assert(I.sizeof % T.sizeof == 0);
		enum itemSize = I.sizeof / T.sizeof;

		I res;

		static if (I.sizeof >=  8) (*cast(T[itemSize]*)&res)[0] = pop();
		static if (I.sizeof >= 16) (*cast(T[itemSize]*)&res)[1] = pop();
		static if (I.sizeof >= 24) (*cast(T[itemSize]*)&res)[2] = pop();
		static if (I.sizeof >= 32) (*cast(T[itemSize]*)&res)[3] = pop();
		static if (I.sizeof >= 40) (*cast(T[itemSize]*)&res)[4] = pop();
		static if (I.sizeof >= 48) (*cast(T[itemSize]*)&res)[5] = pop();
		static if (I.sizeof >= 56) (*cast(T[itemSize]*)&res)[6] = pop();
		static if (I.sizeof >= 64) (*cast(T[itemSize]*)&res)[7] = pop();
		static assert(I.sizeof <= 64);
		return res;
	}

	void pushItem(I)(I item) shared {
		static assert(I.sizeof % T.sizeof == 0);
		enum itemSize = I.sizeof / T.sizeof;
		static if (I.sizeof >=  8) pushDelayed((*cast(T[itemSize]*)&item)[0]);
		static if (I.sizeof >= 16) pushDelayed((*cast(T[itemSize]*)&item)[1]);
		static if (I.sizeof >= 24) pushDelayed((*cast(T[itemSize]*)&item)[2]);
		static if (I.sizeof >= 32) pushDelayed((*cast(T[itemSize]*)&item)[3]);
		static if (I.sizeof >= 40) pushDelayed((*cast(T[itemSize]*)&item)[4]);
		static if (I.sizeof >= 48) pushDelayed((*cast(T[itemSize]*)&item)[5]);
		static if (I.sizeof >= 56) pushDelayed((*cast(T[itemSize]*)&item)[6]);
		static if (I.sizeof >= 64) pushDelayed((*cast(T[itemSize]*)&item)[7]);
		static assert(I.sizeof <= 64);
	}

	void setItem(I)(I item, size_t at) shared {
		static assert(I.sizeof % T.sizeof == 0);
		enum itemSize = I.sizeof / T.sizeof;
		static if (I.sizeof >=  8) _data[at+0 & mask] = (*cast(T[itemSize]*)&item)[0];
		static if (I.sizeof >= 16) _data[at+1 & mask] = (*cast(T[itemSize]*)&item)[1];
		static if (I.sizeof >= 24) _data[at+2 & mask] = (*cast(T[itemSize]*)&item)[2];
		static if (I.sizeof >= 32) _data[at+3 & mask] = (*cast(T[itemSize]*)&item)[3];
		static if (I.sizeof >= 40) _data[at+4 & mask] = (*cast(T[itemSize]*)&item)[4];
		static if (I.sizeof >= 48) _data[at+5 & mask] = (*cast(T[itemSize]*)&item)[5];
		static if (I.sizeof >= 56) _data[at+6 & mask] = (*cast(T[itemSize]*)&item)[6];
		static if (I.sizeof >= 64) _data[at+7 & mask] = (*cast(T[itemSize]*)&item)[7];
		static assert(I.sizeof <= 64);
	}

	void startPush() shared {
		wpos = atomicLoad!(MemoryOrder.acq)(_wpos);
	}

	void endPush() shared {
		atomicStore!(MemoryOrder.rel)(_wpos, wpos);
	}

	// skip to fill in later with setItem
	size_t skipItemDelayed(I)() shared {
		static assert(I.sizeof % T.sizeof == 0);
		enum itemSize = I.sizeof / T.sizeof;
		size_t temp = cast(size_t)wpos;

		foreach(_; 0..itemSize)
		{
			while (wpos - atomicLoad!(MemoryOrder.acq)(_rpos) == capacity) {
				yield();
			}
			++cast(size_t)wpos; // remove shared
		}

		return temp;
	}

	// can cause dead-lock if consumer is waiting for producer.
	// Make sure that there is enough space. Or else keep consuming
	private void pushDelayed(T val) {
		while (wpos - atomicLoad!(MemoryOrder.acq)(_rpos) == capacity) {
			yield();
		}

		_data[wpos & mask] = val;
		++cast(size_t)wpos; // remove shared
	}

	private void push(shared(T) t) shared
	in { assert(!full); }
	body
	{
		immutable pos = atomicLoad!(MemoryOrder.acq)(_wpos);
		_data[pos & mask] = t;
		atomicStore!(MemoryOrder.rel)(_wpos, pos + 1);
	}

	shared(T) popBlocking() shared {
		while (empty)
			yield();
		return pop();
	}

	static void yield() {
		Thread.yield();
		//infof("yield");
	}

	private shared(T) pop() shared
	in { assert(!empty); }
	body
	{
		immutable pos = atomicLoad!(MemoryOrder.acq)(_rpos);
		auto res = _data[pos & mask];
		atomicStore!(MemoryOrder.rel)(_rpos, pos + 1);
		return res;
	}

private:
	enum mask = capacity - 1;

	size_t wpos;
	size_t _wpos;
	size_t _rpos;
	T[] _data;
}

private:

template roundPow2(size_t v) {
	import core.bitop : bsr;
	enum roundPow2 = v ? cast(size_t)1 << bsr(v) : 0;
}
