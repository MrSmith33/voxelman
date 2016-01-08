/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.config.plugin;

import pluginlib;
import voxelman.core.config;
import voxelman.config.configmanager;

version(SIDE_CLIENT)
	enum string CONFIG_FILE_NAME = "../../config/client.sdl";
else version(SIDE_SERVER)
	enum string CONFIG_FILE_NAME = "../../config/server.sdl";
else
	enum string CONFIG_FILE_NAME = "../../config/config.sdl";

shared static this()
{
	pluginRegistry.regClientPlugin(new ConfigPlugin);
	pluginRegistry.regServerPlugin(new ConfigPlugin);
}

final class ConfigPlugin : IPlugin
{
	mixin IdAndSemverFrom!(voxelman.config.plugininfo);

	override void registerResourceManagers(void delegate(IResourceManager) reg)
	{
		reg(new ConfigManager(CONFIG_FILE_NAME));
	}
}
