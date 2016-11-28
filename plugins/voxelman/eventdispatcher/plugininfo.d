module voxelman.eventdispatcher.plugininfo;
enum id = "voxelman.eventdispatcher";
enum semver = "0.5.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

shared static this()
{
	import pluginlib;
	import voxelman.eventdispatcher.plugin;
	pluginRegistry.regClientPlugin(new EventDispatcherPlugin);
	pluginRegistry.regServerPlugin(new EventDispatcherPlugin);
}
