/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.gen.worker;

import std.experimental.logger;

import voxelman.block.utils;
import voxelman.core.config;
import voxelman.utils.worker;
import voxelman.world.storage.coordinates;

import voxelman.world.gen.utils;

//version = DBG_OUT;
void chunkGenWorkerThread(shared(Worker)* workerInfo, BlockInfoTable blockInfos)
{
	import std.array : uninitializedArray;

	ubyte[] compressBuffer = uninitializedArray!(ubyte[])(CHUNK_SIZE_CUBE*BlockId.sizeof);
	try
	{
		while (workerInfo.needsToRun)
		{
			workerInfo.waitForNotify();

			if (!workerInfo.taskQueue.empty)
			{
				ulong _cwp = workerInfo.taskQueue.popItem!ulong();
				ChunkWorldPos cwp = ChunkWorldPos(_cwp);
				GenDelegate generator = workerInfo.taskQueue.popItem!GenDelegate();
				generator(cwp, workerInfo, blockInfos, compressBuffer);
			}
		}
	}
	catch(Throwable t)
	{
		import std.conv : to;
		infof("%s from gen worker", t.to!string);
		throw t;
	}
	version(DBG_OUT)infof("Gen worker stopped");
}
