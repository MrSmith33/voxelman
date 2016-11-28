module test.railroad.plugininfo;
enum id = "test.railroad";
enum semver = "0.7.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

shared static this()
{
	import pluginlib;
	import test.railroad.plugin;
	pluginRegistry.regClientPlugin(new RailroadPluginClient);
	pluginRegistry.regServerPlugin(new RailroadPluginServer);
}
