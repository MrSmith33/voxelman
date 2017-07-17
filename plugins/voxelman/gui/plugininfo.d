module voxelman.gui.plugininfo;
enum id = "voxelman.gui";
enum semver = "0.5.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

import pluginlib.pluginregistry;
void register(ref PluginRegistry registry)
{
	import voxelman.gui.plugin;
	pluginRegistry.regClientPlugin(new GuiPlugin);
}
