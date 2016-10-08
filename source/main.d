/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module main;

import std.file : mkdirRecurse;
import std.getopt;

import voxelman.log;
import pluginlib;

void main(string[] args)
{
	mkdirRecurse("../logs");

	enum AppType { client, server, combined }
	AppType appType;

	std.getopt.getopt(args,
		std.getopt.config.passThrough,
		std.getopt.config.required,
		"app", &appType);

	scope(exit) closeBinLog();

	final switch(appType) with(AppType)
	{
		case client:
			setupLogger("../logs/client.log");
			initBinLog("../logs/client.bin");
			pluginRegistry.clientMain(args, true/*dedicated*/);
			break;
		case server:
			setupLogger("../logs/server.log");
			initBinLog("../logs/server.bin");
			pluginRegistry.serverMain(args, true/*dedicated*/);
			break;
		case combined:
			setupLogger("../logs/client.log");
			initBinLog("../logs/client.bin");
			pluginRegistry.clientMain(args, false/*combined*/);
			break;
	}
}
