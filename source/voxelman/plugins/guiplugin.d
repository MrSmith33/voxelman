/**
Copyright: Copyright (c) 2014-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.plugins.guiplugin;

import plugin;

class GuiPlugin : IPlugin
{
	override string name() @property { return "GuiPlugin"; }
	override string semver() @property { return "1.0.0"; }
	override void preInit() { }

	override void init(IPluginManager pluginman) { }

	override void postInit() { }

	void update(double delta)
	{

	}

	void addTemplate(string temlateName)
	{

	}

private:

}
