module voxelman.movement.plugininfo;
enum id = "voxelman.movement";
enum semver = "0.5.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

shared static this()
{
	import pluginlib;
	import voxelman.movement.plugin;
	pluginRegistry.regClientPlugin(new MovementPlugin);
}
