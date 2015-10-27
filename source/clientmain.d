/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.clientmain;

import std.file : mkdirRecurse;

import voxelman.utils.log;
import plugin.pluginregistry;
import voxelman.client.clientplugin;

void main(string[] args)
{
	mkdirRecurse("../logs");
	setupLogger("../logs/client.log");
	auto c = new ClientPlugin;
	pluginRegistry.regClientPlugin(c);
	c.run(args);
}
