module voxelman.edit.plugininfo;
enum id = "voxelman.edit";
enum semver = "0.5.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

import pluginlib.pluginregistry;
void register(ref PluginRegistry registry)
{
	import voxelman.edit.plugin;
	pluginRegistry.regClientPlugin(new EditPlugin);
}
