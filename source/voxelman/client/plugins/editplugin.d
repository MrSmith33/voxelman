/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.client.plugins.editplugin;

import std.experimental.logger;

import plugin;
import voxelman.config;
import voxelman.plugins.inputplugin;
import voxelman.plugins.eventdispatcherplugin;
import voxelman.client.clientplugin;
import voxelman.client.plugins.worldinteractionplugin;


class EditPlugin : IPlugin
{
	ClientPlugin clientPlugin;
	WorldInteractionPlugin worldInteraction;
	InputPlugin input;

	BlockType currentBlock = 4;

	// IPlugin stuff
	override string name() @property { return "EditPlugin"; }
	override string semver() @property { return "0.5.0"; }

	override void init(IPluginManager pluginman)
	{
		clientPlugin = pluginman.getPlugin!ClientPlugin(this);
		input = pluginman.getPlugin!InputPlugin(this);
		worldInteraction = pluginman.getPlugin!WorldInteractionPlugin(this);
	}

	override void postInit()
	{
		input.registerKeyBinding(new KeyBinding(PointerButton.PB_1, "key.mainAction", null, &onMainActionRelease));
		input.registerKeyBinding(new KeyBinding(PointerButton.PB_2, "key.secondaryAction", null, &onSecondaryActionRelease));
		input.registerKeyBinding(new KeyBinding(PointerButton.PB_3, "key.tertiaryAction", null, &onTertiaryActionRelease));
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
