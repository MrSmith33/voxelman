/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.gui.plugin;

import voxelman.log;
import std.string : format;
import voxelman.math;
import derelict.imgui.imgui;

import voxelman.platform.iwindow;
import voxelman.platform.glfwwindow;
import voxelman.platform.input;
import voxelman.graphics.irenderer;
import voxelman.graphics.oglrenderer;

import pluginlib;
import voxelman.imgui_glfw;

import voxelman.core.config;
import voxelman.core.events;
import voxelman.world.storage;

import voxelman.dbg.plugin;
import voxelman.eventdispatcher.plugin;
import voxelman.config.configmanager;
import voxelman.input.keybindingmanager;


struct ClosePressedEvent {}


final class GuiPlugin : IPlugin
{
private:
	EventDispatcherPlugin evDispatcher;
	ConfigOption resolution;

public:
	IWindow window;
	IRenderer renderer;
	ImguiState igState;
	bool mouseLocked;

	mixin IdAndSemverFrom!"voxelman.gui.plugininfo";

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto config = resmanRegistry.getResourceManager!ConfigManager;
		resolution = config.registerOption!(int[])("resolution", [1280, 720]);

		KeyBindingManager keyBindingMan = resmanRegistry.getResourceManager!KeyBindingManager;
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_Q, "key.lockMouse", null, &onLockMouse));
	}

	override void preInit()
	{
		import voxelman.graphics.gl;

		loadOpenGL();

		window = new GlfwWindow();
		window.init(ivec2(resolution.get!(int[])), "Voxelman client");

		reloadOpenGL();

		renderer = new OglRenderer(window);
		igState.init((cast(GlfwWindow)window).handle);

		// Bind events
		window.windowResized.connect(&windowResized);
		window.closePressed.connect(&closePressed);

		window.keyPressed.connect(&igState.onKeyPressed);
		window.keyReleased.connect(&igState.onKeyReleased);
		window.charEntered.connect(&igState.charCallback);
		window.mousePressed.connect(&igState.onMousePressed);
		window.mouseReleased.connect(&igState.onMouseReleased);
		window.wheelScrolled.connect(&igState.scrollCallback);
	}

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onPreUpdateEvent);
		evDispatcher.subscribeToEvent(&onRender3Event);
		evDispatcher.subscribeToEvent(&onGameStopEvent);

		auto debugClient = pluginman.getPlugin!DebugClient;
		debugClient.registerDebugGuiHandler(&showDebugSettings, SETTINGS_ORDER, "Q Lock mouse");
	}

	private void showDebugSettings()
	{
		igCheckbox("[Q] Lock mouse", &mouseLocked);
		updateMouseLock();
	}

	private void onPreUpdateEvent(ref PreUpdateEvent event)
	{
		updateMouseLock();
		window.processEvents();
		igState.newFrame();
	}

	private void onRender3Event(ref Render3Event event)
	{
		igState.render();
	}

	private void onGameStopEvent(ref GameStopEvent stopEvent)
	{
		window.releaseWindow;
		igState.shutdown();
	}

	private void windowResized(ivec2 newSize)
	{
		evDispatcher.postEvent(WindowResizedEvent(newSize));
	}

	private void closePressed()
	{
		evDispatcher.postEvent(ClosePressedEvent());
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
