module voxelman.remotecontrol.plugininfo;
enum id = "voxelman.remotecontrol";
enum semver = "0.5.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

import pluginlib.pluginregistry;
void register(ref PluginRegistry registry)
{
	import voxelman.remotecontrol.plugin;
	pluginRegistry.regClientPlugin(new RemoteControl!true);
	pluginRegistry.regServerPlugin(new RemoteControl!false);
}
