module voxelman.world.plugininfo;
enum id = "voxelman.world";
enum semver = "0.6.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

shared static this()
{
	import pluginlib;
	import voxelman.world.serverworld;
	import voxelman.world.clientworld;
	pluginRegistry.regClientPlugin(new ClientWorld);
	pluginRegistry.regServerPlugin(new ServerWorld);
}
