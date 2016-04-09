/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.utils.log;

import std.experimental.logger;
import std.stdio : stdout, File;

class ConciseLogger : FileLogger
{
	this(File file, const LogLevel lv = LogLevel.info) @safe
	{
		super(file, lv);
	}

	this(in string fn, const LogLevel lv = LogLevel.info) @safe
	{
		super(fn, lv);
	}

	override protected void beginLogMsg(string file, int line, string funcName,
		string prettyFuncName, string moduleName, LogLevel logLevel,
		Tid threadId, SysTime timestamp, Logger logger)
		@safe
	{
		// empty
	}
}

void setupLogger(string filename)
{
	globalLogLevel = LogLevel.trace;

	auto logger = new MultiLogger;

	auto file = File(filename, "w");
	auto fileLogger = new FileLogger(file);
	fileLogger.logLevel = LogLevel.trace;

	auto conciseLogger = new ConciseLogger(stdout);
	fileLogger.logLevel = LogLevel.info;

	logger.insertLogger("fileLogger", fileLogger);
	logger.insertLogger("stdoutLogger", conciseLogger);

	sharedLog = logger;
}
