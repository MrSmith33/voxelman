/**
Copyright: Copyright (c) 2015-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.gui.plugin;

import voxelman.log;
import std.string : format;
import voxelman.math;

import voxelman.platform.iwindow;
import voxelman.platform.input;
import voxelman.gui;
import voxelman.graphics;
import voxelman.graphics.plugin;
import voxelman.text.linebuffer;

import pluginlib;

import voxelman.core.config;
import voxelman.core.events;
import voxelman.world.storage;

import voxelman.dbg.plugin;
import voxelman.eventdispatcher.plugin;
import voxelman.input.keybindingmanager;

struct ClosePressedEvent {}


final class GuiPlugin : IPlugin
{
private:
	EventDispatcherPlugin evDispatcher;
	GraphicsPlugin graphics;

public:
	GuiContext guictx;
	IWindow window;
	bool mouseLocked;
	bool isGuiDebuggerShown;

	mixin IdAndSemverFrom!"voxelman.gui.plugininfo";

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto keyBindingMan = resmanRegistry.getResourceManager!KeyBindingManager;
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_Q, "key.lockMouse", null, &onLockMouse));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_F9, "key.toggle_gui_dbg", null, (s){isGuiDebuggerShown.toggle_bool;}));
		auto res = resmanRegistry.getResourceManager!GraphicsResources;
		guictx = res.guictx;
	}

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onPreUpdateEvent);

		auto debugClient = pluginman.getPlugin!DebugClient;
		debugClient.registerDebugGuiHandler(&showDebugSettings, SETTINGS_ORDER, "Q Lock mouse");

		graphics = pluginman.getPlugin!GraphicsPlugin;
		window = graphics.window;

		auto debugger_frame = createGuiDebugger(guictx.getRoot(1));
		debugger_frame.visible_if(() => isGuiDebuggerShown);
	}

	private void showDebugSettings()
	{
		//igCheckbox("[Q] Lock mouse", &mouseLocked);
		updateMouseLock();
	}

	private void onPreUpdateEvent(ref PreUpdateEvent event)
	{
		updateMouseLock();
	}

	private void onLockMouse(string)
	{
		mouseLocked = !mouseLocked;
		updateMouseLock();
	}

	private void updateMouseLock()
	{
		if (window.isCursorLocked != mouseLocked)
		{
			window.isCursorLocked = mouseLocked;
			if (mouseLocked)
				window.mousePosition = cast(ivec2)(window.size) / 2;
		}
	}
}
