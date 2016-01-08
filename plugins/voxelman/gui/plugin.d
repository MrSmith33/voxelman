/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.gui.plugin;

import std.experimental.logger;
import std.string : format;
import dlib.math.vector;

import anchovy.fpshelper;
import anchovy.glfwwindow;
import anchovy.input;
import anchovy.irenderer;
import anchovy.iwindow;
import anchovy.oglrenderer;

import tharsis.prof : Zone;

import pluginlib;
import voxelman.imgui_glfw;

import voxelman.core.config;
import voxelman.core.events;
import voxelman.storage.chunk;
import voxelman.storage.coordinates;
import voxelman.storage.utils;

import voxelman.eventdispatcher.plugin;
import voxelman.config.configmanager;


struct ClosePressedEvent {
	import tharsis.prof : Profiler;
	Profiler profiler;
	bool continuePropagation = true;
}

shared static this()
{
	pluginRegistry.regClientPlugin(new GuiPlugin);
}

final class GuiPlugin : IPlugin
{
private:
	EventDispatcherPlugin evDispatcher;
	ConfigOption resolution;
	ConfigOption maxFpsOpt;

public:
	IWindow window;
	IRenderer renderer;
	FpsHelper fpsHelper;
	ImguiState igState;

	mixin IdAndSemverFrom!(voxelman.gui.plugininfo);

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto config = resmanRegistry.getResourceManager!ConfigManager;
		resolution = config.registerOption!(uint[])("resolution", [1280, 720]);
		maxFpsOpt = config.registerOption!uint("max_fps", true);
	}

	override void preInit()
	{
		initLibs();

		window = new GlfwWindow();
		window.init(uvec2(resolution.get!(uint[])), "Voxelman client");
		renderer = new OglRenderer(window);
		igState.init((cast(GlfwWindow)window).handle);

		fpsHelper.maxFps = maxFpsOpt.get!uint;
		if (fpsHelper.maxFps == 0) fpsHelper.limitFps = false;

		// Bind events
		window.windowResized.connect(&windowResized);
		window.closePressed.connect(&closePressed);

		window.keyPressed.connect(&igState.onKeyPressed);
		window.keyReleased.connect(&igState.onKeyReleased);
		window.charEntered.connect(&igState.charCallback);
		window.mousePressed.connect(&igState.onMousePressed);
		window.mouseReleased.connect(&igState.onMouseReleased);
		window.wheelScrolled.connect((dvec2 s) => igState.scrollCallback(s.y));
	}

	void initLibs()
	{
		import derelict.glfw3.glfw3;
		import derelict.opengl3.gl3;
		import derelict.imgui.imgui;
		import voxelman.utils.libloader;

		DerelictGL3.load();
		DerelictGLFW3.load([getLibName(BUILD_TO_ROOT_PATH, "glfw3")]);
		DerelictImgui.load(getLibName(BUILD_TO_ROOT_PATH, "cimgui"));
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
		fpsHelper.update(event.deltaTime);
		igState.newFrame();
	}

	void onRender3Event(ref Render3Event event)
	{
		Zone drawSceneZone = Zone(event.profiler, "drawGui");
		igState.render();
	}

	void onGameStopEvent(ref GameStopEvent stopEvent)
	{
		window.releaseWindow;
		igState.shutdown();
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
