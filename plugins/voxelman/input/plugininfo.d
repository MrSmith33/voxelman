module voxelman.input.plugininfo;
enum id = "voxelman.input";
enum semver = "0.5.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

shared static this()
{
	import pluginlib;
	import voxelman.input.plugin;
	pluginRegistry.regClientPlugin(new InputPlugin);
}
