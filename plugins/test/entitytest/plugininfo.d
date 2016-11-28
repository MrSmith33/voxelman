module test.entitytest.plugininfo;
enum id = "test.entitytest";
enum semver = "1.0.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

shared static this()
{
	import pluginlib;
	import test.entitytest.plugin;
	pluginRegistry.regClientPlugin(new EntityTestPlugin!true);
	pluginRegistry.regServerPlugin(new EntityTestPlugin!false);
}
