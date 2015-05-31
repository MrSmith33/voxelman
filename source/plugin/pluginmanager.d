/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module plugin.pluginmanager;

import std.experimental.logger;
import std.string : format;
import plugin;
import voxelman.config;

/// Simple implementation of IPluginManager
class PluginManager : IPluginManager
{
	IPlugin[string] plugins;

	void registerPlugin(IPlugin pluginInstance)
	{
		assert(pluginInstance);
		assert(pluginInstance.name !in plugins,
			format("Duplicate plugin registered: name=\"%s\" type=\"%s\"",
				pluginInstance.name, pluginInstance));
		plugins[pluginInstance.name] = pluginInstance;
	}

	void loadConfig(Config config)
	{
		foreach(IPlugin p; plugins)
		{
			p.loadConfig(config);
		}
	}

	void initPlugins()
	{
		infof("Loading %s plugins", plugins.length);
		foreach(IPlugin p; plugins)
		{
			p.preInit();
		}
		foreach(IPlugin p; plugins)
		{
			p.init(this);
		}

		size_t i = 1;
		foreach(IPlugin p; plugins)
		{
			p.postInit();
			infof("Loaded #%s %s %s", i, p.name, p.semver);
			++i;
		}
	}

	IPlugin findPlugin(IPlugin requester, string pluginName)
	{
		if (auto plug = pluginName in plugins)
			return *plug;
		else
			throw new Exception(format("Plugin %s requested plugin %s that was not registered",
				requester, pluginName));
	}
}
