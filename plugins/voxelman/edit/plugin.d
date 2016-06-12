/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.edit.plugin;

import std.experimental.logger;

import pluginlib;
import voxelman.core.events;

import voxelman.client.plugin;
import voxelman.worldinteraction.plugin;
import voxelman.graphics.plugin;
import voxelman.net.plugin;
import voxelman.eventdispatcher.plugin;
import voxelman.input.keybindingmanager;

import voxelman.edit.tools.filltool;

shared static this()
{
	pluginRegistry.regClientPlugin(new EditPlugin);
}

abstract class ITool
{
	string name;
	size_t id;
	void onUpdate() {}
	void onMainActionPress() {}
	void onMainActionRelease() {}
	void onSecondaryActionPress() {}
	void onSecondaryActionRelease() {}
	void onTertiaryActionPress() {}
	void onTertiaryActionRelease() {}
}

final class NullTool : ITool
{
	this() { name = "voxelman.edit.null_tool"; }
}

import voxelman.utils.mapping;
class EditPlugin : IPlugin
{
	mixin IdAndSemverFrom!(voxelman.edit.plugininfo);

	size_t selectedTool;
	Mapping!ITool tools;
	NullTool nullTool;
	FillTool fillTool;

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto keyBindingsMan = resmanRegistry.getResourceManager!KeyBindingManager;
		keyBindingsMan.registerKeyBinding(new KeyBinding(PointerButton.PB_1, "key.mainAction", &onMainActionPress, &onMainActionRelease));
		keyBindingsMan.registerKeyBinding(new KeyBinding(PointerButton.PB_2, "key.secondaryAction", &onSecondaryActionPress, &onSecondaryActionRelease));
		keyBindingsMan.registerKeyBinding(new KeyBinding(PointerButton.PB_3, "key.tertiaryAction", &onTertiaryActionPress, &onTertiaryActionRelease));
		keyBindingsMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_RIGHT, "key.next_tool", null, &nextTool));
		keyBindingsMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_LEFT, "key.prev_tool", null, &prevTool));
	}

	override void preInit() {
		nullTool = new NullTool;
		fillTool = new FillTool;
		registerTool(fillTool);
	}

	override void init(IPluginManager pluginman)
	{
		fillTool.connection = pluginman.getPlugin!NetClientPlugin;
		fillTool.clientPlugin = pluginman.getPlugin!ClientPlugin;
		fillTool.worldInteraction = pluginman.getPlugin!WorldInteractionPlugin;
		fillTool.graphics = pluginman.getPlugin!GraphicsPlugin;

		EventDispatcherPlugin evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onUpdateEvent);
	}

	void registerTool(ITool tool)
	{
		assert(tool);
		tools.put(tool);
	}

	void nextTool(string) {
		selectedTool = (selectedTool+1) % tools.length;
	}

	void prevTool(string) {
		selectedTool = (selectedTool-1) % tools.length;
	}

	ITool currentTool() @property {
		if (selectedTool < tools.length)
			return tools[selectedTool];
		return nullTool;
	}

	void onUpdateEvent(ref UpdateEvent event) {
		currentTool.onUpdate();
	}
	void onMainActionPress(string key) {
		currentTool.onMainActionPress();
	}
	void onMainActionRelease(string key) {
		currentTool.onMainActionRelease();
	}
	void onSecondaryActionPress(string key) {
		currentTool.onSecondaryActionPress();
	}
	void onSecondaryActionRelease(string key) {
		currentTool.onSecondaryActionRelease();
	}
	void onTertiaryActionPress(string key) {
		currentTool.onTertiaryActionPress();
	}
	void onTertiaryActionRelease(string key) {
		currentTool.onTertiaryActionRelease();
	}
}
