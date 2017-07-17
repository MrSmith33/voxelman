module voxelman.dbg.plugininfo;
enum id = "voxelman.dbg";
enum semver = "0.6.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

import pluginlib.pluginregistry;
void register(ref PluginRegistry registry)
{
	import voxelman.dbg.plugin;
	pluginRegistry.regClientPlugin(new DebugClient);
	pluginRegistry.regServerPlugin(new DebugServer);
}
