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
import voxelman.world.storage.coordinates;
import voxelman.world.storage.volume;

import voxelman.client.plugin;
import voxelman.worldinteraction.plugin;
import voxelman.graphics.plugin;

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
		clientPlugin = pluginman.getPlugin!ClientPlugin;
		worldInteraction = pluginman.getPlugin!WorldInteractionPlugin;
		graphics = pluginman.getPlugin!GraphicsPlugin;
		EventDispatcherPlugin evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onUpdateEvent);
	}

	void onUpdateEvent(ref UpdateEvent event)
	{
		selection = volumeFromCorners(startingPos.vector, currentCursorPos.vector);
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
		state = EditState.removing;
		startingPos = currentCursorPos;
		worldInteraction.showCursor = false;
	}

	void onMainActionRelease(string key)
	{
		if (!clientPlugin.mouseLocked) return;
		if (state != EditState.removing) return;
		state = EditState.none;
		foreach(pos; selection.positions)
			worldInteraction.placeBlockAt(1, BlockWorldPos(pos));
		worldInteraction.showCursor = true;
	}

	void onSecondaryActionPress(string key)
	{
		if (!clientPlugin.mouseLocked) return;
		if (state != EditState.none) return;
		state = EditState.placing;
		startingPos = currentCursorPos;
		worldInteraction.showCursor = false;
	}

	void onSecondaryActionRelease(string key)
	{
		if (!clientPlugin.mouseLocked) return;
		if (state != EditState.placing) return;
		state = EditState.none;
		foreach(pos; selection.positions)
			worldInteraction.placeBlockAt(currentBlock, BlockWorldPos(pos));
		worldInteraction.showCursor = true;
	}

	void onTertiaryActionRelease(string key)
	{
		if (!clientPlugin.mouseLocked) return;
		currentBlock = worldInteraction.pickBlock();
	}
}
