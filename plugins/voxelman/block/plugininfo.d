module voxelman.block.plugininfo;
enum id = "voxelman.block";
enum semver = "0.6.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

shared static this()
{
	import pluginlib;
	import voxelman.block.plugin;
	pluginRegistry.regClientPlugin(new BlockPluginClient);
	pluginRegistry.regServerPlugin(new BlockPluginServer);
}
