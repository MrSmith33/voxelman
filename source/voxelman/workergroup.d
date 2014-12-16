/**
Copyright: Copyright (c) 2013-2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.workergroup;

import core.atomic : atomicStore;
import std.concurrency : Tid, spawnLinked, send, prioritySend;

struct WorkerGroup(uint numWorkers, alias workerFun)
{
	import std.traits : ParameterTypeTuple;

	private bool _areWorkersStarted;
	private uint _nextWorker;
	private Tid[] _workers;
	private shared bool _areWorkersRunning;

	void startWorkers(ParameterTypeTuple!workerFun args)
	{
		if (_areWorkersStarted) return;
		atomicStore(_areWorkersRunning, true);
		foreach(_; 0..numWorkers)
			_workers ~= spawnLinked(&workerFun, args);
		foreach(worker; _workers)
			worker.send(&_areWorkersRunning);
		_areWorkersStarted = true;
	}

	Tid nextWorker() @property
	{
		_nextWorker %= numWorkers;
		return _workers[_nextWorker++];
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