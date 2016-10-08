/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.log.binlog;

import core.sync.mutex;
import std.stdio : File;

import voxelman.utils.filewriter;
import cbor;

void binlog(T...)(T args) {
	logger.log(args);
}

void initBinLog(string filename) {
	logger.open(filename);
}

void closeBinLog() {
	logger.close();
}

private __gshared BinLogger logger;

private struct BinLogger
{
	Mutex mutex;
	File file;
	FileWriter writer;

	void open(string filename)
	{
		file.open(filename, "wb+");
		writer = FileWriter(file);
		mutex = new Mutex;
	}

	void log(T...)(T args)
	{
		synchronized(mutex)
		{
			encodeCborArrayHeader(writer, args.length);
			foreach(arg; args)
			{
				encodeCbor(writer, arg);
			}
		}
	}

	void close()
	{
		synchronized(mutex)
		{
			writer.flush();
			file.close();
		}
		destroy(mutex);
	}
}
