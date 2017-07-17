module voxelman.movement.plugininfo;
enum id = "voxelman.movement";
enum semver = "0.5.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

import pluginlib.pluginregistry;
void register(ref PluginRegistry registry)
{
	import voxelman.movement.plugin;
	pluginRegistry.regClientPlugin(new MovementPlugin);
}
