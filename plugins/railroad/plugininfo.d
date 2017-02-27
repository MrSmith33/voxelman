module railroad.plugininfo;
enum id = "railroad";
enum semver = "0.9.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

shared static this()
{
	import pluginlib;
	import railroad.plugin;
	pluginRegistry.regClientPlugin(new RailroadPluginClient);
	pluginRegistry.regServerPlugin(new RailroadPluginServer);
}
