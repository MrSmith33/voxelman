/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.client.plugins.editplugin;

import std.experimental.logger;

import plugin;
import voxelman.config;
import voxelman.client.clientplugin;
import voxelman.client.plugins.worldinteractionplugin;

import voxelman.plugins.eventdispatcherplugin;
import voxelman.managers.keybindingmanager;

shared static this()
{
	pluginRegistry.regClientPlugin(new EditPlugin);
}

class EditPlugin : IPlugin
{
	ClientPlugin clientPlugin;
	WorldInteractionPlugin worldInteraction;

	BlockType currentBlock = 4;

	// IPlugin stuff
	override string id() @property { return "voxelman.client.editplugin"; }
	override string semver() @property { return "0.5.0"; }

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto keyBindingsMan = resmanRegistry.getResourceManager!KeyBindingManager;
		keyBindingsMan.registerKeyBinding(new KeyBinding(PointerButton.PB_1, "key.mainAction", null, &onMainActionRelease));
		keyBindingsMan.registerKeyBinding(new KeyBinding(PointerButton.PB_2, "key.secondaryAction", null, &onSecondaryActionRelease));
		keyBindingsMan.registerKeyBinding(new KeyBinding(PointerButton.PB_3, "key.tertiaryAction", null, &onTertiaryActionRelease));
	}

	override void init(IPluginManager pluginman)
	{
		clientPlugin = pluginman.getPlugin!ClientPlugin;
		worldInteraction = pluginman.getPlugin!WorldInteractionPlugin;
	}

	void onMainActionRelease(string key)
	{
		if (clientPlugin.mouseLocked)
			worldInteraction.placeBlock(1);
	}

	void onSecondaryActionRelease(string key)
	{
		if (clientPlugin.mouseLocked)
			worldInteraction.placeBlock(currentBlock);
	}

	void onTertiaryActionRelease(string key)
	{
		if (clientPlugin.mouseLocked)
			currentBlock = worldInteraction.pickBlock();
	}
}
