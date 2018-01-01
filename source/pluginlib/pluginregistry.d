/**
Copyright: Copyright (c) 2015-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module pluginlib.pluginregistry;

import voxelman.log;
import std.exception;
import pluginlib;

/// register plugins here inside shared static this
__gshared PluginRegistry pluginRegistry;

alias ClientMain = void delegate(string[] args);
alias ServerMain = void delegate(string[] args, ServerMode);

enum ServerMode
{
	standalone,
	internal
}

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

	void regClientMain(ClientMain clientMain)
	{
		this.clientMain = clientMain;
	}
	void regServerMain(ServerMain serverMain)
	{
		this.serverMain = serverMain;
	}

	IPlugin[TypeInfo] clientPlugins;
	IPlugin[TypeInfo] serverPlugins;
	ClientMain clientMain;
	ServerMain serverMain;
}
