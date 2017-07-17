module voxelman.block.plugininfo;
enum id = "voxelman.block";
enum semver = "0.6.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

import pluginlib.pluginregistry;
void register(ref PluginRegistry registry)
{
	import voxelman.block.plugin;
	registry.regClientPlugin(new BlockPluginClient);
	registry.regServerPlugin(new BlockPluginServer);
}
