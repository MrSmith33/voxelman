module voxelman.worldinteraction.plugininfo;
enum id = "voxelman.worldinteraction";
enum semver = "0.5.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

import pluginlib.pluginregistry;
void register(ref PluginRegistry registry)
{
	import voxelman.worldinteraction.plugin;
	pluginRegistry.regClientPlugin(new WorldInteractionPlugin);
}
