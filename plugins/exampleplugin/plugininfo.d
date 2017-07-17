module exampleplugin.plugininfo;
enum id = "exampleplugin";
enum semver = "0.1.0";
enum deps = ["voxelman.eventdispatcher", "0.3.0"];
enum clientdeps = ["voxelman.configplugin", "0.5.0", "voxelman.client", "0.5.0"];
enum serverdeps = ["voxelman.server", "0.5.0"];

import pluginlib.pluginregistry;
void register(ref PluginRegistry registry)
{
	import exampleplugin.client;
	import exampleplugin.server;
	pluginRegistry.regClientPlugin(new ExamplePluginClient);
	pluginRegistry.regServerPlugin(new ExamplePluginServer);
}
