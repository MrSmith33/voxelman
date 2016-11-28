module test.avatar.plugininfo;
enum id = "test.avatar";
enum semver = "1.0.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

shared static this()
{
	import pluginlib;
	import test.avatar.plugin;
	pluginRegistry.regClientPlugin(new AvatarClient);
	pluginRegistry.regServerPlugin(new AvatarServer);
}
