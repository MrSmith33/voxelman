module plugin.ipluginmanager;

import plugin;

interface IPluginManager
{
	/// Returns reference to plugin instance if pluginName was registered.
	IPlugin findPlugin(IPlugin requester, string pluginName);
}

P getPlugin(P)(IPluginManager modman, IPlugin requester, string pluginName = P.stringof)
{
	import std.exception : enforce;
	IPlugin mod = modman.findPlugin(requester, pluginName);
	P exactPlugin = cast(P)mod;
	enforce(exactPlugin);
	return exactPlugin;
}