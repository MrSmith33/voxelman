/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module pluginlib.interfaces;

import voxelman.log;
import std.conv : to;
import std.string : format;
import pluginlib;

mixin template IdAndSemverFrom(string pinfoModuleName)
{
	mixin("import pinfo = " ~ pinfoModuleName ~ ";");
	override string id() @property { return pinfo.id; }
	override string semver() @property { return pinfo.semver; }
}

/// Basic plugin interface
abstract class IPlugin
{
	/// Unique identifier ("exampleplugin")
	string id() @property;
	/// Human readable name ("Example plugin")
	//string name() @property;
	/// Valid semver version string. i.e. 0.1.0-rc.1
	string semver() @property;
	/// Register resource managers provided by this plugin
	void registerResourceManagers(void delegate(IResourceManager) registerResourceManager) {}
	/// Get references to resource managers and call their methods.
	/// Resources are loaded before preInit
	void registerResources(IResourceManagerRegistry resmanRegistry) {}
	/// Private initialization using resources loaded by resource managers
	void preInit() {}
	/// Get references to other plugins. Other plugins may call this plugin from now
	void init(IPluginManager pluginman) {}
	/// Called after init. Do something with data retrieved at previous stage
	void postInit() {}
}

interface IPluginManager
{
	/// Returns reference to plugin instance if pluginId was registered.
	IPlugin findPlugin(TypeInfo pluginType);
	IPlugin findPluginById(string pluginId);

	/// Returns null if plugin is not loaded, P otherwise
	final P findPlugin(P)()
	{
		import std.exception : enforce;
		IPlugin plugin = findPlugin(typeid(P));
		if (!plugin) return null;

		P exactPlugin = cast(P)plugin;
		enforce(exactPlugin, format("Cannot cast plugin to '%s'", typeid(P)));
		return exactPlugin;
	}

	/// Guaranteed to return not null reference to P
	final P getPlugin(P)()
	{
		import std.exception : enforce;
		IPlugin plugin = findPlugin(typeid(P));
		P exactPlugin = cast(P)plugin;
		enforce(exactPlugin, format("Cannot find plugin '%s'", typeid(P)));
		return exactPlugin;
	}
}

/// Basic plugin interface
/// Resource manager version is the same as plugin's one that registered it
abstract class IResourceManager
{
	/// Unique identifier ("config")
	string id() @property;
	/// Human readable name ("Config resource manager")
	//string name() @property;
	/// Load/create needed resources
	void preInit() {}
	/// Get references to other plugins
	void init(IResourceManagerRegistry resmanRegistry) {}
	/// Called after init. Do something with data retrieved at previous stage
	void loadResources() {}
	/// Called after loadResources. Do something with data retrieved at previous stage
	void postInit() {}
}

interface IResourceManagerRegistry
{
	/// Returns reference to ResourceManager instance if resmanId was registered
	IResourceManager findResourceManager(TypeInfo rmType);

	/// Guaranteed to return not null reference to RM
	final RM getResourceManager(RM)()
	{
		import std.exception : enforce;
		IResourceManager resman = findResourceManager(typeid(RM));
		RM exactResman = cast(RM)resman;
		enforce(exactResman, format("Cannot find resource manager '%s'", typeid(RM)));
		return exactResman;
	}
}
