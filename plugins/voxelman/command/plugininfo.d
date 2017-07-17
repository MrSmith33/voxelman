module voxelman.command.plugininfo;
enum id = "voxelman.command";
enum semver = "0.5.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

import pluginlib.pluginregistry;
void register(ref PluginRegistry registry)
{
	import voxelman.command.plugin;
	pluginRegistry.regClientPlugin(new CommandPluginClient);
	pluginRegistry.regServerPlugin(new CommandPluginServer);
}
