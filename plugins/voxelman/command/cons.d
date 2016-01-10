/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.command.cons;

shared static this()
{
	import pluginlib;
	import voxelman.command.plugin;
	pluginRegistry.regClientPlugin(new CommandPluginClient);
	pluginRegistry.regServerPlugin(new CommandPluginServer);
}
