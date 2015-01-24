/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.modules.guimodule;

import modular;

class GuiModule : IModule
{
	override string name() @property { return "GuiModule"; }
	override string semver() @property { return "1.0.0"; }
	override void preInit() { }

	override void init(IModuleManager moduleman) { }

	override void postInit() { }

	void update(double delta)
	{
		
	}

	void addTemplate(string temlateName)
	{

	}

private:
	
}