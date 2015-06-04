/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module plugin.ipluginmanager;

import plugin;

interface IPluginManager
{
	/// Returns reference to plugin instance if pluginName was registered.
	IPlugin findPlugin(IPlugin requester, string pluginName);
}

P getPlugin(P)(IPluginManager pluginman, IPlugin requester, string pluginName = P.stringof)
{
	import std.exception : enforce;
	IPlugin plugin = pluginman.findPlugin(requester, pluginName);
	P exactPlugin = cast(P)plugin;
	enforce(exactPlugin);
	return exactPlugin;
}
