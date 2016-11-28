module voxelman.blockentity.plugininfo;
enum id = "voxelman.blockentity";
enum semver = "0.7.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

shared static this()
{
	import pluginlib;
	import voxelman.blockentity.plugin;
	pluginRegistry.regClientPlugin(new BlockEntityClient);
	pluginRegistry.regServerPlugin(new BlockEntityServer);
}
