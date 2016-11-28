module voxelman.session.plugininfo;
enum id = "voxelman.session";
enum semver = "0.8.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

shared static this()
{
	import pluginlib;
	import voxelman.session.server;
	import voxelman.session.client;
	pluginRegistry.regClientPlugin(new ClientSession);
	pluginRegistry.regServerPlugin(new ClientManager);
}
