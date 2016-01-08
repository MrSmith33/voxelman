/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module servermain;

import std.file : mkdirRecurse;

import voxelman.utils.log;
import pluginlib;

void main(string[] args)
{
	mkdirRecurse("../logs");
	setupLogger("../logs/server.log");
	pluginRegistry.serverMain(args);
}
