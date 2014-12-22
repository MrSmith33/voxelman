/**
Copyright: Copyright (c) 2013-2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.workergroup;

import core.atomic : atomicStore;
import std.concurrency : Tid, spawn, send, prioritySend;

struct WorkerGroup(alias workerFun)
{
	import std.traits : ParameterTypeTuple;

	private bool _areWorkersStarted;
	private uint _nextWorker;
	private Tid[] _workers;
	private uint _numWorkers;
	private shared bool _areWorkersRunning;

	void startWorkers(uint numWorkers, ParameterTypeTuple!workerFun args)
	{
		if (_areWorkersStarted) return;
		_numWorkers = numWorkers;
		atomicStore(_areWorkersRunning, true);
		foreach(_; 0.._numWorkers)
			_workers ~= spawn(&workerFun, args);
		foreach(worker; _workers)
			worker.send(&_areWorkersRunning);
		_areWorkersStarted = true;
	}

	Tid nextWorker() @property
	{
		_nextWorker %= _numWorkers;
		return _workers[_nextWorker++];
	}

	void stopWorkersWhenDone()
	{
		atomicStore(_areWorkersRunning, false);
		foreach(worker; _workers)
			worker.send(0);
		_areWorkersStarted = false;
	}

	void stopWorkers()
	{
		foreach(worker; _workers)
			worker.prioritySend(0);
		atomicStore(_areWorkersRunning, false);
		_areWorkersStarted = false;
	}
}

void atomicStoreLocal(T)(ref T var, auto ref T value)
{
	atomicStore(*cast(shared(T)*)(&var), cast(shared(T))value);
}

T atomicLoadLocal(T)(ref const T var)
{
	return cast(T)atomicLoad(*cast(shared(const T)*)(&var));
}