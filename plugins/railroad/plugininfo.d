module railroad.plugininfo;
enum id = "railroad";
enum semver = "0.9.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

import pluginlib.pluginregistry;
void register(ref PluginRegistry registry)
{
	import railroad.plugin;
	pluginRegistry.regClientPlugin(new RailroadPluginClient);
	pluginRegistry.regServerPlugin(new RailroadPluginServer);
}
