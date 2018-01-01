/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.edit.plugin;

import voxelman.log;

import pluginlib;
import voxelman.core.events;
import dlib.math.utils;
import voxelman.text.textformatter;

import voxelman.core.config;
import voxelman.eventdispatcher.plugin;
import voxelman.graphics.plugin;
import voxelman.block.plugin;
import voxelman.command.plugin;
import voxelman.gui.plugin;
import voxelman.dbg.plugin;
import voxelman.net.plugin;
import voxelman.worldinteraction.plugin;
import voxelman.input.keybindingmanager;

import voxelman.edit.tools.itool;
import voxelman.edit.tools.filltool;

final class NullTool : ITool
{
	this() { name = "voxelman.edit.null_tool"; }
}

import voxelman.utils.mapping;
class EditPlugin : IPlugin
{
	mixin IdAndSemverFrom!"voxelman.edit.plugininfo";

	size_t selectedTool;
	GuiPlugin guiPlugin;
	GraphicsPlugin graphics;
	BlockManager blockManager;
	Mapping!ITool tools;
	NullTool nullTool;
	FillTool fillTool;

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		blockManager = resmanRegistry.getResourceManager!BlockManager;
		auto keyBindingsMan = resmanRegistry.getResourceManager!KeyBindingManager;
		keyBindingsMan.registerKeyBinding(new KeyBinding(PointerButton.PB_1, "key.mainAction", &onMainActionPress, &onMainActionRelease));
		keyBindingsMan.registerKeyBinding(new KeyBinding(PointerButton.PB_2, "key.secondaryAction", &onSecondaryActionPress, &onSecondaryActionRelease));
		keyBindingsMan.registerKeyBinding(new KeyBinding(PointerButton.PB_3, "key.tertiaryAction", &onTertiaryActionPress, &onTertiaryActionRelease));
		keyBindingsMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_RIGHT, "key.next_tool", null, &nextTool));
		keyBindingsMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_LEFT, "key.prev_tool", null, &prevTool));
		keyBindingsMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_R, "key.rotateAction", null, &onRotateAction));
	}

	override void preInit() {
		nullTool = new NullTool;
		fillTool = new FillTool;
		registerTool(fillTool);
	}

	override void init(IPluginManager pluginman)
	{
		fillTool.connection = pluginman.getPlugin!NetClientPlugin;
		fillTool.worldInteraction = pluginman.getPlugin!WorldInteractionPlugin;
		fillTool.blockInfos = blockManager.getBlocks();

		graphics = pluginman.getPlugin!GraphicsPlugin;
		guiPlugin = pluginman.getPlugin!GuiPlugin;
		EventDispatcherPlugin evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onUpdateEvent);
		evDispatcher.subscribeToEvent(&onRenderEvent);

		auto debugClient = pluginman.getPlugin!DebugClient;
		debugClient.registerDebugGuiHandler(&showToolName, INFO_ORDER, "Tool");
		debugClient.registerDebugGuiHandler(&showToolHandler, INFO_ORDER, "ToolDebug");

		auto commandPlugin = pluginman.getPlugin!CommandPluginClient;
		commandPlugin.registerCommand(CommandInfo("pick", &onPickBlockName, ["<block_name>"], "Picks a block by name"));
	}

	private void showToolName() {
		//igTextf("Tool: %s", currentTool.name);
	}

	private void showToolHandler() {
		currentTool.onShowDebug();
	}

	void onPickBlockName(CommandParams params) {
		if (params.args.length > 1)
		{
			size_t blockId = blockManager.getId(params.args[1]);
			if (blockId == size_t.max)
			{
				// no block
				infof("no block '%s'", params.args[1]);
			}
			else
			{
				fillTool.currentBlock = BlockIdAndMeta(cast(BlockId)blockId);
			}
		}
	}

	void registerTool(ITool tool) {
		assert(tool);
		tools.put(tool);
	}

	void nextTool(string) {
		selectedTool = selectedTool+1;
		if (selectedTool > tools.length-1)
			selectedTool = 0;
	}

	void prevTool(string) {
		selectedTool = clamp(selectedTool-1, 0, tools.length-1);
	}

	ITool currentTool() @property {
		if (selectedTool < tools.length)
			return tools[selectedTool];
		return nullTool;
	}

	void onUpdateEvent(ref UpdateEvent event) {
		currentTool.onUpdate();
	}
	void onRenderEvent(ref RenderSolid3dEvent event) {
		currentTool.onRender(graphics);
	}
	void onMainActionPress(string key) {
		if (!guiPlugin.mouseLocked) return;
		currentTool.onMainActionPress();
	}
	void onMainActionRelease(string key) {
		if (!guiPlugin.mouseLocked) return;
		currentTool.onMainActionRelease();
	}
	void onSecondaryActionPress(string key) {
		if (!guiPlugin.mouseLocked) return;
		currentTool.onSecondaryActionPress();
	}
	void onSecondaryActionRelease(string key) {
		if (!guiPlugin.mouseLocked) return;
		currentTool.onSecondaryActionRelease();
	}
	void onTertiaryActionPress(string key) {
		if (!guiPlugin.mouseLocked) return;
		currentTool.onTertiaryActionPress();
	}
	void onTertiaryActionRelease(string key) {
		if (!guiPlugin.mouseLocked) return;
		currentTool.onTertiaryActionRelease();
	}
	void onRotateAction(string key) {
		if (!guiPlugin.mouseLocked) return;
		currentTool.onRotateAction();
	}
}
