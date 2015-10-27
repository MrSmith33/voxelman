/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.servermain;

import std.file : mkdirRecurse;

import voxelman.utils.log;
import plugin;
import voxelman.server.serverplugin;

void main(string[] args)
{
	mkdirRecurse("../logs");
	setupLogger("../logs/server.log");
	auto c = new ServerPlugin;
	pluginRegistry.regServerPlugin(c);
	c.run(args);
}
