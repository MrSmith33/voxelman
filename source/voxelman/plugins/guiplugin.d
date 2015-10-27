/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.plugins.guiplugin;

import std.experimental.logger;
import std.string : format;

import anchovy.core.interfaces.iwindow;
import anchovy.graphics.windows.glfwwindow;
import anchovy.gui.application.application;
import anchovy.gui;
public import anchovy.core.input;
import tharsis.prof : Zone;


import plugin;

import voxelman.config;
import voxelman.storage.chunk;
import voxelman.storage.coordinates;
import voxelman.storage.utils;
import voxelman.events;

import voxelman.plugins.eventdispatcherplugin;
import voxelman.managers.configmanager;


struct ClosePressedEvent {
	import tharsis.prof : Profiler;
	Profiler profiler;
	bool continuePropagation = true;
}

static this()
{
	pluginRegistry.regClientPlugin(new GuiPlugin);
}

final class GuiPlugin : IPlugin
{
private:
	EventDispatcherPlugin evDispatcher;
	Application!GlfwWindow application;
	ConfigOption resolution;

public:

	IRenderer renderer() @property
	{
		return application.renderer;
	}

	IWindow window() @property
	{
		return application.window;
	}

	GuiContext context() @property
	{
		return application.context;
	}

	ref FpsHelper fpsHelper() @property
	{
		return application.fpsHelper;
	}

	override string id() @property { return "voxelman.plugins.guiplugin"; }
	override string semver() @property { return "0.5.0"; }

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto config = resmanRegistry.getResourceManager!ConfigManager;
		resolution = config.registerOption!(uint[])("resolution", [1280, 720]);
	}

	override void preInit()
	{
		application = new Application!GlfwWindow();
		application.init([], uvec2(resolution.get!(uint[])), "Voxelman client");
		appLoad();
	}

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onPreUpdateEvent);
		evDispatcher.subscribeToEvent(&onRender3Event);
		evDispatcher.subscribeToEvent(&onGameStopEvent);
	}

	void onPreUpdateEvent(ref PreUpdateEvent event)
	{
		Zone drawSceneZone = Zone(event.profiler, "updateGui");
		window.processEvents();
		application.update(event.deltaTime);
	}

	void onRender3Event(ref Render3Event event)
	{
		Zone drawSceneZone = Zone(event.profiler, "drawGui");
		application.context.eventDispatcher.draw();
	}

	void onGameStopEvent(ref GameStopEvent stopEvent)
	{
		application.window.releaseWindow;
	}

	void addHideHandler(string frameId)
	{
		auto frame = application.context.getWidgetById(frameId);
		Widget closeButton = frame["subwidgets"].get!(Widget[string])["close"];
		closeButton.addEventHandler(delegate bool(Widget widget, PointerClickEvent event){
			frame["isVisible"] = false;
			return true;
		});
	}

	void setupFrameShowButton(string buttonId, string frameId)
	{
		auto frame = application.context.getWidgetById(frameId);
		application.context.getWidgetById(buttonId).addEventHandler(delegate bool(Widget widget, PointerClickEvent event){
			frame["isVisible"] = true;
			return true;
		});
	}

	string[] getHardwareInfo()
	{
		return application.getHardwareInfo();
	}

	void appLoad()
	{
		fpsHelper.limitFps = false;

		// Bind events
		window.windowResized.connect(&windowResized);
		window.closePressed.connect(&closePressed);

		// ----------------------------- Creating widgets -----------------------------
		application.templateManager.parseFile("voxelman.sdl");

		auto mainLayer = application.context.createWidget("mainLayer");
		application.context.addRoot(mainLayer);

		auto frameLayer = application.context.createWidget("frameLayer");
		application.context.addRoot(frameLayer);

		// Frames
		addHideHandler("infoFrame");
		addHideHandler("settingsFrame");

		setupFrameShowButton("showInfo", "infoFrame");
		setupFrameShowButton("showSettings", "settingsFrame");
	}

	private void windowResized(uvec2 newSize)
	{
		evDispatcher.postEvent(WindowResizedEvent(newSize));
	}

	private void closePressed()
	{
		evDispatcher.postEvent(ClosePressedEvent());
	}
}
