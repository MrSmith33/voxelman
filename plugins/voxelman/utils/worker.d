/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.utils.worker;

import std.concurrency : spawn, Tid;
import std.string : format;
import core.atomic;
import core.sync.semaphore;
import core.sync.condition;
import core.sync.mutex;
import core.thread : Thread;

import voxelman.core.config : QUEUE_LENGTH;
import voxelman.utils.sharedqueue;

alias MessageQueue = SharedQueue!(QUEUE_LENGTH);

shared struct Worker
{
	Thread thread;
	bool running = true;
	MessageQueue taskQueue;
	MessageQueue resultQueue;
	Semaphore workAvaliable;

	// for owner
	void alloc(string debugName = "W") shared {
		taskQueue.alloc(format("%s_task", debugName));
		resultQueue.alloc(format("%s_res", debugName));
		workAvaliable = cast(shared) new Semaphore();
	}

	// for owner
	void stop() shared {
		atomicStore(running, false);
		(cast(Semaphore)workAvaliable).notify();
	}

	void notify() shared {
		(cast(Semaphore)workAvaliable).notify();
	}

	// for worker
	void signalStopped() shared {
		atomicStore(running, false);
	}

	bool isRunning() shared @property {
		return atomicLoad!(MemoryOrder.acq)(running) && (cast(Thread)thread).isRunning;
	}

	bool isStopped() shared @property const {
		return !(cast(Thread)thread).isRunning;
	}

	bool queuesEmpty() shared @property const {
		return taskQueue.empty && resultQueue.empty;
	}

	// for owner
	void free() shared {
		taskQueue.free();
		resultQueue.free();
	}
}

Thread spawnWorker(F, T...)(F fn, T args)
{
	void exec()
	{
		fn( args );
	}
	auto t = new Thread(&exec);
    t.start();
    return t;
}

shared struct WorkerGroup
{
	import std.traits : ParameterTypeTuple;

	private bool _areWorkersStarted;
	private size_t _nextWorker;
	private uint _numWorkers;
	private bool _areWorkersRunning;

	Worker[] workers;
	size_t numWorkers;

	void startWorkers(F, T...)(size_t _numWorkers, F fn, T args) shared
	{
		import std.algorithm.comparison : clamp;

		if (_areWorkersStarted) return;

		numWorkers = clamp(_numWorkers, 1, 16);
		queueLengths.length = numWorkers;
		workers.length = numWorkers;

		foreach(ref worker; workers)
		{
			worker.alloc();
			worker.thread = cast(shared)spawnWorker(fn, &worker, args);
		}

		_areWorkersStarted = true;
	}

	private static struct QLen {size_t i; size_t len;}
	private QLen[] queueLengths;

	shared(Worker)* nextWorker() shared @property
	{
		import std.algorithm : sort;
		foreach(i; 0..numWorkers)
		{
			queueLengths[i].i = i;
			queueLengths[i].len = workers[i].taskQueue.length;
		}
		sort!((a,b) => a.len < b.len)(queueLengths);// balance worker queues
		//_nextWorker = (_nextWorker + 1) % numWorkers; // round robin
		return &workers[queueLengths[0].i];
	}

	bool queuesEmpty()
	{
		bool empty = true;
		foreach(ref worker; workers) empty = empty && worker.queuesEmpty;
		return empty;
	}

	bool allWorkersStopped()
	{
		bool stopped = true;
		foreach(ref worker; workers) stopped = stopped && worker.isStopped;
		return stopped;
	}

	void stop() shared
	{
		foreach(ref worker; workers)
		{
			worker.stop();
		}

		while (!allWorkersStopped())
		{
			Thread.yield();
		}

		free();
	}

	void free() shared
	{
		foreach(ref w; workers)
		{
			w.free();
		}
	}
}
