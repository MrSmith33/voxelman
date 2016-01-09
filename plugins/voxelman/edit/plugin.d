/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.edit.plugin;

import std.experimental.logger;

import pluginlib;
import voxelman.core.config;
import voxelman.client.plugin;
import voxelman.worldinteraction.plugin;

import voxelman.eventdispatcher.plugin;
import voxelman.input.keybindingmanager;

shared static this()
{
	pluginRegistry.regClientPlugin(new EditPlugin);
}

class EditPlugin : IPlugin
{
	mixin IdAndSemverFrom!(voxelman.edit.plugininfo);

	ClientPlugin clientPlugin;
	WorldInteractionPlugin worldInteraction;

	BlockId currentBlock = 4;

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
