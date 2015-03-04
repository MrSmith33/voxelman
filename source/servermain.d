/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.servermain;

import voxelman.utils.log;
import voxelman.server.serverplugin;

void main(string[] args)
{
	setupLogger("server.log");
	auto serverPlugin = new ServerPlugin;
	serverPlugin.run(args);
}
