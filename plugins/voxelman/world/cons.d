/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.cons;

shared static this()
{
	import pluginlib;
	import voxelman.world.serverworld;
	import voxelman.world.clientworld;
	pluginRegistry.regClientPlugin(new ClientWorld);
	pluginRegistry.regServerPlugin(new ServerWorld);
}
