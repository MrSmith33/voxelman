// Taken from https://github.com/MartinNowak/lock-free/blob/master/src/lock_free/rwqueue.d
module voxelman.utils.lockfreequeue;

import core.atomic;

/**
 * A lock-free single-reader, single-writer FIFO queue.
 */
shared struct ProducerConsumerQueue(T, size_t capacity = roundPow2!(PAGE_SIZE / T.sizeof))
{
	static assert(capacity > 0, "Cannot have a capacity of 0.");
	static assert(roundPow2!capacity == capacity, "The capacity must be a power of 2");

	@property size_t length() shared const
	{
		return atomicLoad!(MemoryOrder.acq)(_wpos) - atomicLoad!(MemoryOrder.acq)(_rpos);
	}

	@property bool empty() shared const
	{
		return !length;
	}

	@property bool full() const
	{
		return length == capacity;
	}

	void push(shared(T) t)
	in { assert(!full); }
	body
	{
		immutable pos = atomicLoad!(MemoryOrder.acq)(_wpos);
		_data[pos & mask] = t;
		atomicStore!(MemoryOrder.rel)(_wpos, pos + 1);
	}

	shared(T) pop()
	in { assert(!empty); }
	body
	{
		immutable pos = atomicLoad!(MemoryOrder.acq)(_rpos);
		auto res = _data[pos & mask];
		atomicStore!(MemoryOrder.rel)(_rpos, pos + 1);
		return res;
	}

private:
	//    import std.algorithm; // move

	enum mask = capacity - 1;

	size_t _wpos;
	size_t _rpos;
	T[capacity] _data;
}

private:

enum PAGE_SIZE = 4096;

template roundPow2(size_t v)
{
	import core.bitop : bsr;
	enum roundPow2 = v ? cast(size_t)1 << bsr(v) : 0;
}

static assert(roundPow2!0 == 0);
static assert(roundPow2!3 == 2);
static assert(roundPow2!4 == 4);

version (unittest)
{
	import core.thread, std.concurrency;
	enum amount = 10_000;

	void push(T)(ref shared(ProducerConsumerQueue!T) queue)
	{
		foreach (i; 0 .. amount)
		{
			while (queue.full)
				Thread.yield();
			queue.push(cast(shared T)i);
		}
	}

	void pop(T)(ref shared(ProducerConsumerQueue!T) queue)
	{
		foreach (i; 0 .. amount)
		{
			while (queue.empty)
				Thread.yield();
			assert(queue.pop() == cast(shared T)i);
		}
	}
}

unittest
{
	shared(ProducerConsumerQueue!size_t) queue;
	auto t0 = new Thread({push(queue);}),
		t1 = new Thread({pop(queue);});
	t0.start(); t1.start();
	t0.join(); t1.join();
}

unittest
{
	static struct Data { size_t i; }
	shared(ProducerConsumerQueue!Data) queue;
	auto t0 = new Thread({push(queue);}),
		t1 = new Thread({pop(queue);});
	t0.start(); t1.start();
	t0.join(); t1.join();
}
