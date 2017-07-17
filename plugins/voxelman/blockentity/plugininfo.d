module voxelman.blockentity.plugininfo;
enum id = "voxelman.blockentity";
enum semver = "0.7.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

import pluginlib.pluginregistry;
void register(ref PluginRegistry registry)
{
	import voxelman.blockentity.plugin;
	pluginRegistry.regClientPlugin(new BlockEntityClient);
	pluginRegistry.regServerPlugin(new BlockEntityServer);
}
