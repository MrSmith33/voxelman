module voxelman.worldinteraction.plugininfo;
enum id = "voxelman.worldinteraction";
enum semver = "0.5.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

shared static this()
{
	import pluginlib;
	import voxelman.worldinteraction.plugin;
	pluginRegistry.regClientPlugin(new WorldInteractionPlugin);
}
