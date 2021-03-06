/**
Copyright: Copyright (c) 2015-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.config.plugin;

import pluginlib;
import voxelman.core.config;
public import voxelman.config.configmanager;

enum string CONFIG_FILE_NAME_CLIENT = "../../config/client.sdl";
enum string CONFIG_FILE_NAME_SERVER = "../../config/server.sdl";

final class ConfigPlugin : IPlugin
{
	mixin IdAndSemverFrom!"voxelman.config.plugininfo";
	string configFileName;
	string[] args;

	this(string configFileName, string[] args)
	{
		this.configFileName = configFileName;
		this.args = args;
	}

	override void registerResourceManagers(void delegate(IResourceManager) reg)
	{
		reg(new ConfigManager(configFileName, args));
	}
}
