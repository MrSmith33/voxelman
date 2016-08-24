/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module pluginlib.pluginregistry;

import std.experimental.logger;
import std.exception;
import pluginlib;

/// register plugins here inside shared static this
__gshared PluginRegistry pluginRegistry;

alias MainDel = void delegate(string[] args, bool dedicated);

struct PluginRegistry
{
	void regClientPlugin(P : IPlugin)(P plug)
	{
		enforce(plug, "null plugin instance");
		errorf(!!(typeid(plug) in clientPlugins),
			"%s is already registered as client plugin", plug.id);
		clientPlugins[typeid(plug)] = plug;
	}
	void regServerPlugin(P : IPlugin)(P plug)
	{
		enforce(plug, "null plugin instance");
		errorf(!!(typeid(plug) in serverPlugins),
			"%s is already registered as server plugin", plug.id);
		serverPlugins[typeid(plug)] = plug;
	}

	void regClientMain(MainDel clientMain)
	{
		this.clientMain = clientMain;
	}
	void regServerMain(MainDel serverMain)
	{
		this.serverMain = serverMain;
	}

	IPlugin[TypeInfo] clientPlugins;
	IPlugin[TypeInfo] serverPlugins;
	MainDel clientMain;
	MainDel serverMain;
}
