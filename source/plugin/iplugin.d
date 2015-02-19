/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module plugin.iplugin;

import plugin;

/// Basic plugin interface.
interface IPlugin
{
	// i.e. "Test Plugin"
	string name() @property;
	// valid semver version string. i.e. 0.1.0-rc.1
	string semver() @property;
	// load/create needed resources
	void preInit();
	// get references to other plugins
	void init(IPluginManager pluginman);
	// called after init. Do something with data retrieved at previous stage.
	void postInit();
}
