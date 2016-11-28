module voxelman.dbg.plugininfo;
enum id = "voxelman.dbg";
enum semver = "0.6.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

shared static this()
{
	import pluginlib;
	import voxelman.dbg.plugin;
	pluginRegistry.regClientPlugin(new DebugClient);
	pluginRegistry.regServerPlugin(new DebugServer);
}
