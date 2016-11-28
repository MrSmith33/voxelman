module voxelman.client.plugininfo;
enum id = "voxelman.client";
enum semver = "0.5.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

shared static this()
{
	import pluginlib;
	import voxelman.client.plugin;
	auto c = new ClientPlugin;
	pluginRegistry.regClientPlugin(c);
	pluginRegistry.regClientMain(&c.run);
}
