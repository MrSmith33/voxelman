/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.config.plugin;

import pluginlib;
import voxelman.core.config;
public import voxelman.config.configmanager;

enum string CONFIG_FILE_NAME_CLIENT = "../../config/client.sdl";
enum string CONFIG_FILE_NAME_SERVER = "../../config/server.sdl";

shared static this()
{
	pluginRegistry.regClientPlugin(new ConfigPlugin(true));
	pluginRegistry.regServerPlugin(new ConfigPlugin(false));
}

final class ConfigPlugin : IPlugin
{
	mixin IdAndSemverFrom!(voxelman.config.plugininfo);
	string configFileName;

	this(bool client)
	{
		if (client)
			configFileName = CONFIG_FILE_NAME_CLIENT;
		else
			configFileName = CONFIG_FILE_NAME_SERVER;
	}

	override void registerResourceManagers(void delegate(IResourceManager) reg)
	{
		reg(new ConfigManager(configFileName));
	}
}
