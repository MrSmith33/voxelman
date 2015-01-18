/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.modules.guimodule;

import modular;

import modular.modules.mainloopmodule;

class GuiModule : IModule, IUpdatableModule
{
	override string name() @property { return "GuiModule"; }
	override string semver() @property { return "1.0.0"; }
	override void load()
	{
	}

	override void init(IModuleManager moduleman)
	{
		mainmod = moduleman.getModule!MainLoopModule(this);
		mainmod.registerUpdatableModule(this);
	}

	void update(double delta)
	{
		
	}

	void addTemplate(string temlateName)
	{

	}

private:
	MainLoopModule mainmod;
}