module voxelman.graphics.plugininfo;
enum id = "voxelman.graphics";
enum semver = "0.5.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

shared static this()
{
	import pluginlib;
	import voxelman.graphics.plugin;
	pluginRegistry.regClientPlugin(new GraphicsPlugin);
}
