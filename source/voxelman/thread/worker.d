/**
Copyright: Copyright (c) 2013-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.thread.worker;

import std.concurrency : spawn, Tid;
import std.string : format;
import core.atomic;
import core.sync.semaphore;
import core.sync.condition;
import core.sync.mutex;
import core.thread : Thread;

public import voxelman.thread.sharedqueue;

enum QUEUE_LENGTH = 1024*1024*1;
enum MAX_LOAD_QUEUE_LENGTH = QUEUE_LENGTH / 2;

shared struct Worker
{
	Thread thread;
	bool running = true;
	SharedQueue taskQueue;
	SharedQueue resultQueue;
	size_t groupIndex;
	// also notified on stop
	Semaphore workAvaliable;

	// for owner
	void alloc(size_t groupIndex = 0, string debugName = "W", size_t capacity = QUEUE_LENGTH) shared {
		taskQueue.alloc(format("%s_task", debugName), capacity);
		resultQueue.alloc(format("%s_res", debugName), capacity);
		workAvaliable = cast(shared) new Semaphore();
		this.groupIndex = groupIndex;
	}

	void stop() shared {
		atomicStore(running, false);
		(cast(Semaphore)workAvaliable).notify();
	}

	void notify() shared {
		(cast(Semaphore)workAvaliable).notify();
	}

	void signalStopped() shared {
		atomicStore(running, false);
	}

	bool isRunning() shared @property {
		return (cast(Thread)thread).isRunning;
	}

	bool isStopped() shared @property const {
		return !(cast(Thread)thread).isRunning;
	}

	void free() shared {
		taskQueue.free();
		resultQueue.free();
	}

	// for worker
	void waitForNotify() shared const {
		(cast(Semaphore)workAvaliable).wait();
	}

	bool needsToRun() shared @property {
		return atomicLoad!(MemoryOrder.acq)(running);
	}

	bool queuesEmpty() shared @property const {
		return taskQueue.empty && resultQueue.empty;
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
	t.isDaemon = true;
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
		if (_areWorkersStarted) return;

		numWorkers = _numWorkers;
		queueLengths.length = numWorkers;
		workers.length = numWorkers;

		foreach(i, ref worker; workers)
		{
			worker.alloc(i);
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
		foreach(ref worker; workers) empty = empty && (worker.queuesEmpty || worker.isStopped);
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
