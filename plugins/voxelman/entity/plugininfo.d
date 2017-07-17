module voxelman.entity.plugininfo;
enum id = "voxelman.entity";
enum semver = "0.5.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

import pluginlib.pluginregistry;
void register(ref PluginRegistry registry)
{
	import voxelman.entity.plugin;
	pluginRegistry.regClientPlugin(new EntityPluginClient);
	pluginRegistry.regServerPlugin(new EntityPluginServer);
}
