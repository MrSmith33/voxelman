/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.edit.plugin;

import std.experimental.logger;

import pluginlib;
import voxelman.core.config;
import voxelman.core.events;
import voxelman.core.packets;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.volume;

import voxelman.client.plugin;
import voxelman.worldinteraction.plugin;
import voxelman.graphics.plugin;
import voxelman.net.plugin;

import voxelman.eventdispatcher.plugin;
import voxelman.input.keybindingmanager;

shared static this()
{
	pluginRegistry.regClientPlugin(new EditPlugin);
}

enum EditState
{
	none,
	placing,
	removing
}

class EditPlugin : IPlugin
{
	mixin IdAndSemverFrom!(voxelman.edit.plugininfo);

	ClientPlugin clientPlugin;
	WorldInteractionPlugin worldInteraction;
	GraphicsPlugin graphics;
	NetClientPlugin connection;

	BlockId currentBlock = 4;
	BlockWorldPos startingPos;
	EditState state;
	Volume selection;

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto keyBindingsMan = resmanRegistry.getResourceManager!KeyBindingManager;
		keyBindingsMan.registerKeyBinding(new KeyBinding(PointerButton.PB_1, "key.mainAction", &onMainActionPress, &onMainActionRelease));
		keyBindingsMan.registerKeyBinding(new KeyBinding(PointerButton.PB_2, "key.secondaryAction", &onSecondaryActionPress, &onSecondaryActionRelease));
		keyBindingsMan.registerKeyBinding(new KeyBinding(PointerButton.PB_3, "key.tertiaryAction", null, &onTertiaryActionRelease));
	}

	override void init(IPluginManager pluginman)
	{
		connection = pluginman.getPlugin!NetClientPlugin;
		clientPlugin = pluginman.getPlugin!ClientPlugin;
		worldInteraction = pluginman.getPlugin!WorldInteractionPlugin;
		graphics = pluginman.getPlugin!GraphicsPlugin;
		EventDispatcherPlugin evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onUpdateEvent);
	}

	void onUpdateEvent(ref UpdateEvent event)
	{
		if (currentCursorPos.w != startingPos.w)
		{
			startingPos = currentCursorPos;
		}
		selection = volumeFromCorners(startingPos.vector.xyz, currentCursorPos.vector.xyz, cast(DimentionId)currentCursorPos.w);
		drawSelection();
	}

	BlockWorldPos currentCursorPos() @property
	{
		final switch(state) {
			case EditState.none: return worldInteraction.blockPos;
			case EditState.placing:
				return worldInteraction.sideBlockPos;
			case EditState.removing:
				return worldInteraction.blockPos;
		}
	}

	void drawSelection()
	{
		final switch(state) {
			case EditState.none:
				break;
			case EditState.placing:
				graphics.debugBatch.putCube(vec3(selection.position), vec3(selection.size), Colors.blue, false);
				break;
			case EditState.removing:
				graphics.debugBatch.putCube(vec3(selection.position), vec3(selection.size), Colors.red, false);
				break;
		}
	}

	void onMainActionPress(string key)
	{
		if (!clientPlugin.mouseLocked) return;
		if (state != EditState.none) return;
		if (!worldInteraction.cursorHit) return;
		state = EditState.removing;
		startingPos = currentCursorPos;
		worldInteraction.showCursor = false;
	}

	void onMainActionRelease(string key)
	{
		if (!clientPlugin.mouseLocked) return;
		if (state != EditState.removing) return;
		state = EditState.none;
		worldInteraction.showCursor = true;

		if (worldInteraction.cursorHit)
		{
			fillVolume(selection, 1);
		}
	}

	void onSecondaryActionPress(string key)
	{
		if (!clientPlugin.mouseLocked) return;
		if (state != EditState.none) return;
		if (!worldInteraction.cursorHit) return;
		state = EditState.placing;
		startingPos = currentCursorPos;
		worldInteraction.showCursor = false;
	}

	void onSecondaryActionRelease(string key)
	{
		if (!clientPlugin.mouseLocked) return;
		if (state != EditState.placing) return;
		state = EditState.none;
		worldInteraction.showCursor = true;

		if (worldInteraction.cursorHit)
		{
			fillVolume(selection, currentBlock);
		}
	}

	void onTertiaryActionRelease(string key)
	{
		if (!clientPlugin.mouseLocked) return;
		currentBlock = worldInteraction.pickBlock();
	}

	void fillVolume(Volume volume, BlockId blockId)
	{
		connection.send(FillBlockVolumePacket(volume, blockId));
	}
}
