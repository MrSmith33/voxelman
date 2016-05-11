/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module clientmain;

import std.file : mkdirRecurse;
import std.getopt;

import voxelman.utils.log;
import pluginlib;

void main(string[] args)
{
	mkdirRecurse("../logs");

	enum AppType { client, server }
	AppType appType;

	std.getopt.getopt(args,
		std.getopt.config.passThrough,
		std.getopt.config.required,
		"app", &appType);

	if (appType == AppType.client)
	{
		setupLogger("../logs/client.log");
		pluginRegistry.clientMain(args);
	}
	else if (appType == AppType.server)
	{
		setupLogger("../logs/server.log");
		pluginRegistry.serverMain(args);
	}
}
