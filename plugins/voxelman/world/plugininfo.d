module voxelman.world.plugininfo;
enum id = "voxelman.world";
enum semver = "0.6.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

import pluginlib.pluginregistry;
void register(ref PluginRegistry registry)
{
	import voxelman.world.serverworld;
	import voxelman.world.clientworld;
	pluginRegistry.regClientPlugin(new ClientWorld);
	pluginRegistry.regServerPlugin(new ServerWorld);
}
