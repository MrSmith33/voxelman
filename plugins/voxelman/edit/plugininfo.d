module voxelman.edit.plugininfo;
enum id = "voxelman.edit";
enum semver = "0.5.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

shared static this()
{
	import pluginlib;
	import voxelman.edit.plugin;
	pluginRegistry.regClientPlugin(new EditPlugin);
}
