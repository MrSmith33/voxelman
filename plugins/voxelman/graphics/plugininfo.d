module voxelman.graphics.plugininfo;
enum id = "voxelman.graphics";
enum semver = "0.5.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

import pluginlib.pluginregistry;
void register(ref PluginRegistry registry)
{
	import voxelman.graphics.plugin;
	pluginRegistry.regClientPlugin(new GraphicsPlugin);
}
