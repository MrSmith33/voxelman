/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module pluginlib.pluginmanager;

import std.experimental.logger;
import std.string : format;
import pluginlib;

class PluginManager : IPluginManager, IResourceManagerRegistry
{
	IPlugin[TypeInfo] plugins;
	IPlugin[string] pluginsById;
	IResourceManager[TypeInfo] resourceManagers;

	void registerPlugin(IPlugin pluginInstance)
	{
		assert(pluginInstance);
		assert(
			typeid(pluginInstance) !in plugins &&
			pluginInstance.id !in pluginsById,
			format("Duplicate plugin registered: id=\"%s\" type=\"%s\"",
				pluginInstance.id, pluginInstance));
		plugins[typeid(pluginInstance)] = pluginInstance;
		pluginsById[pluginInstance.id] = pluginInstance;
	}

	void registerResourceManager(IResourceManager rmInstance)
	{
		assert(rmInstance);
		assert(typeid(rmInstance) !in resourceManagers,
			format("Duplicate resource manager registered: id=\"%s\" type=\"%s\"",
				rmInstance.id, rmInstance));
		resourceManagers[typeid(rmInstance)] = rmInstance;
	}

	// IPluginManager
	IPlugin findPlugin(TypeInfo pluginType)
	{
		return plugins.get(pluginType, null);
	}

	IPlugin findPluginById(string pluginId)
	{
		return pluginsById.get(pluginId, null);
	}


	// IResourceManagerRegistry
	IResourceManager findResourceManager(TypeInfo rmType)
	{
		return resourceManagers.get(rmType, null);
	}

	void initPlugins()
	{
		// Register resources
		foreach(IPlugin p; plugins)
		{
			p.registerResourceManagers(&registerResourceManager);
		}

		foreach(IResourceManager rm; resourceManagers)
		{
			rm.preInit();
		}
		foreach(IResourceManager rm; resourceManagers)
		{
			rm.init(this);
		}

		foreach(IPlugin p; plugins)
		{
			p.registerResources(this);
		}

		// Load resources
		foreach(IResourceManager rm; resourceManagers)
		{
			rm.loadResources();
		}
		foreach(IResourceManager rm; resourceManagers)
		{
			rm.postInit();
		}

		// Load plugins
		foreach(IPlugin p; plugins)
		{
			p.preInit();
		}
		foreach(IPlugin p; plugins)
		{
			p.init(this);
		}

		foreach(IPlugin p; plugins)
		{
			p.postInit();
		}

		size_t i = 1;
		infof("Loaded %s plugins", plugins.length);
		foreach(IPlugin p; plugins)
		{
			infof("Loaded #%s %s %s", i, p.id, p.semver);
			++i;
		}
	}
}
