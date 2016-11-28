module voxelman.chat.plugininfo;
enum id = "voxelman.chat";
enum semver = "0.6.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

shared static this()
{
	import pluginlib;
	import voxelman.chat.plugin;
	pluginRegistry.regClientPlugin(new ChatPluginClient);
	pluginRegistry.regServerPlugin(new ChatPluginServer);
}
