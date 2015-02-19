/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module plugin.pluginmanager;

import std.stdio;
import std.string : format;
import plugin;

/// Simple implementation of IPluginManager
class PluginManager : IPluginManager
{
	IPlugin[string] plugins;

	void registerPlugin(IPlugin pluginInstance)
	{
		assert(pluginInstance);
		plugins[pluginInstance.name] = pluginInstance;
	}

	void initPlugins()
	{
		foreach(IPlugin p; plugins)
		{
			p.preInit();
			writefln("PreInited plugin %s %s", p.name, p.semver);
		}
		foreach(IPlugin p; plugins)
		{
			p.init(this);
			writefln("Inited plugin %s %s", p.name, p.semver);
		}
		foreach(IPlugin p; plugins)
		{
			p.postInit();
			writefln("PostInited plugin %s %s", p.name, p.semver);
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
