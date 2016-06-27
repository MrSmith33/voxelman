/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.blockentity.cons;

shared static this()
{
	import pluginlib;
	import voxelman.blockentity.plugin;
	pluginRegistry.regClientPlugin(new BlockEntityClient);
	pluginRegistry.regServerPlugin(new BlockEntityServer);
}
