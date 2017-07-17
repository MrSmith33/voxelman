module voxelman.input.plugininfo;
enum id = "voxelman.input";
enum semver = "0.5.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

import pluginlib.pluginregistry;
void register(ref PluginRegistry registry)
{
	import voxelman.input.plugin;
	pluginRegistry.regClientPlugin(new InputPlugin);
}
