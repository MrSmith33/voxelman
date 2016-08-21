/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.dbg.cons;

shared static this()
{
	import pluginlib;
	import voxelman.dbg.plugin;
	pluginRegistry.regClientPlugin(new DebugClient);
	pluginRegistry.regServerPlugin(new DebugServer);
}
