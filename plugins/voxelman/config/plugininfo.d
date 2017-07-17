module voxelman.config.plugininfo;
enum id = "voxelman.config";
enum semver = "0.5.0";
enum deps = [];
enum clientdeps = [];
enum serverdeps = [];

import pluginlib.pluginregistry;
void register(ref PluginRegistry registry)
{
	import voxelman.config.plugin;
	import core.runtime : Runtime;
	pluginRegistry.regClientPlugin(new ConfigPlugin(CONFIG_FILE_NAME_CLIENT, Runtime.args));
	pluginRegistry.regServerPlugin(new ConfigPlugin(CONFIG_FILE_NAME_SERVER, Runtime.args));
}
