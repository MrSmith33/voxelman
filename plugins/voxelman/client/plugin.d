/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.client.plugin;

import core.time;
import voxelman.log;

import voxelman.math;
import dlib.math.matrix : Matrix4f;
import derelict.enet.enet;
import derelict.opengl3.gl3;
import derelict.imgui.imgui;

import anchovy.fpshelper;
import anchovy.glerrors;

import netlib;
import pluginlib;

import voxelman.eventdispatcher.plugin;
import voxelman.graphics.plugin;
import voxelman.gui.plugin;
import voxelman.net.plugin;
import voxelman.command.plugin;
import voxelman.block.plugin;
import voxelman.world.clientworld;
import voxelman.dbg.plugin;

import voxelman.core.config;
import voxelman.net.events;
import voxelman.core.events;
import voxelman.core.packets;
import voxelman.net.packets;

import voxelman.config.configmanager;
import voxelman.input.keybindingmanager;

import voxelman.world.mesh.chunkmesh;
import voxelman.world.storage.chunk;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.utils;
import voxelman.world.storage.worldaccess;
import voxelman.utils.textformatter;

import voxelman.client.console;

//version = manualGC;


auto formatDuration(Duration dur)
{
	import std.string : format;
	auto splitted = dur.split();
	return format("%s.%03s,%03s secs",
		splitted.seconds, splitted.msecs, splitted.usecs);
}

final class ClientPlugin : IPlugin
{
private:
	// Plugins
	EventDispatcherPlugin evDispatcher;
	GraphicsPlugin graphics;
	GuiPlugin guiPlugin;
	CommandPluginClient commandPlugin;
	ClientWorld clientWorld;
	NetClientPlugin connection;
	Debugger dbg;

public:
	Console console;
	bool isConsoleShown = false;

	// Client data
	bool isRunning = false;

	double delta;
	Duration targetFrameTime;
	ConfigOption maxFpsOpt;
	ConfigOption limitFpsOpt;
	bool limitFps = true;
	FpsHelper fpsHelper;

	// IPlugin stuff
	mixin IdAndSemverFrom!"voxelman.client.plugininfo";

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		ConfigManager config = resmanRegistry.getResourceManager!ConfigManager;
		maxFpsOpt = config.registerOption!int("max_fps", 120);
		limitFpsOpt = config.registerOption!bool("limit_fps", true);

		dbg = resmanRegistry.getResourceManager!Debugger;

		KeyBindingManager keyBindingMan = resmanRegistry.getResourceManager!KeyBindingManager;
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_GRAVE_ACCENT, "key.toggle_console", null, &onConsoleToggleKey));
	}

	override void preInit()
	{
		fpsHelper.maxFps = maxFpsOpt.get!uint;
		limitFps = limitFpsOpt.get!bool;
		console.init();
	}

	override void init(IPluginManager pluginman)
	{
		clientWorld = pluginman.getPlugin!ClientWorld;
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;

		graphics = pluginman.getPlugin!GraphicsPlugin;
		guiPlugin = pluginman.getPlugin!GuiPlugin;
		auto debugClient = pluginman.getPlugin!DebugClient;
		debugClient.registerDebugGuiHandler(&printFpsDebug, FPS_ORDER, "Fps");

		evDispatcher.subscribeToEvent(&onPreUpdateEvent);
		evDispatcher.subscribeToEvent(&onPostUpdateEvent);
		evDispatcher.subscribeToEvent(&onClosePressedEvent);

		commandPlugin = pluginman.getPlugin!CommandPluginClient;
		commandPlugin.registerCommand("cl_stop|stop", &onStopCommand);

		console.messageWindow.messageHandler = &onConsoleCommand;

		connection = pluginman.getPlugin!NetClientPlugin;
	}

	override void postInit() {}

	void onStopCommand(CommandParams) { isRunning = false; }

	void printFpsDebug()
	{
		igTextf("FPS: %s", fpsHelper.fps); igSameLine();
		int fpsLimitVal = maxFpsOpt.get!int;
		igPushItemWidth(60);
		igSliderInt("##limit_val", &fpsLimitVal, 30, 240, null);
		igPopItemWidth();
		igSameLine();
		igCheckbox("limit##limit_fps_toggle", &limitFps);
		maxFpsOpt.set!int(fpsLimitVal);
		updateFrameTime();
	}

	void run(string[] args)
	{
		import std.datetime : MonoTime, Duration, usecs, dur;
		import core.thread : Thread;

		version(manualGC) GC.disable;

		evDispatcher.postEvent(GameStartEvent());

		MonoTime prevTime = MonoTime.currTime;
		updateFrameTime();

		isRunning = true;
		ulong frame;
		while(isRunning)
		{
			MonoTime newTime = MonoTime.currTime;
			delta = (newTime - prevTime).total!"usecs" / 1_000_000.0;
			prevTime = newTime;

				evDispatcher.postEvent(PreUpdateEvent(delta, frame));
				evDispatcher.postEvent(UpdateEvent(delta, frame));
				evDispatcher.postEvent(PostUpdateEvent(delta, frame));
				evDispatcher.postEvent(DoGuiEvent(frame));
				evDispatcher.postEvent(RenderEvent());

				version(manualGC) {
					auto collectStartTime = MonoTime.currTime;
					GC.collect();
					GC.minimize();
					auto collectDur = MonoTime.currTime - collectStartTime;
					double collectDurFloat = collectDur.total!"usecs" / 1_000.0;
					dbg.logVar("GC, ms", collectDurFloat, 512);
				}

				if (limitFps) {
					Duration updateTime = MonoTime.currTime - newTime;
					Duration sleepTime = targetFrameTime - updateTime;
					if (sleepTime > Duration.zero)
						Thread.sleep(sleepTime);
				}

				++frame;
		}

		infof("Stopping...");
		evDispatcher.postEvent(GameStopEvent());
	}

	void updateFrameTime()
	{
		targetFrameTime = (1_000_000 / maxFpsOpt.get!uint).usecs;
	}

	void onPreUpdateEvent(ref PreUpdateEvent event)
	{
		fpsHelper.update(event.deltaTime);
	}

	void onPostUpdateEvent(ref PostUpdateEvent event)
	{
		import std.compiler;
		static if (version_minor >= 72)
		{
			import core.memory;
			dbg.logVar("GC used", core.memory.GC.stats().usedSize, 128);
			dbg.logVar("GC free", core.memory.GC.stats().freeSize, 128);
		}

		if (isConsoleShown)
			console.draw();
		dbg.logVar("delta, ms", delta*1000.0, 256);

		if (guiPlugin.mouseLocked)
			drawOverlay();
	}

	void onConsoleCommand(string command)
	{
		infof("Executing command '%s'", command);
		ExecResult res = commandPlugin.execute(command, SessionId(0));

		if (res.status == ExecStatus.notRegistered)
		{
			if (connection.isConnected)
				connection.send(CommandPacket(command));
			else
				console.lineBuffer.putfln("Unknown client command '%s', not connected to server", command);
		}
		else if (res.status == ExecStatus.error)
			console.lineBuffer.putfln("Error executing command '%s': %s", command, res.error);
		else
			console.lineBuffer.putln(command);
	}

	void onConsoleToggleKey(string)
	{
		isConsoleShown = !isConsoleShown;
	}

	void onClosePressedEvent(ref ClosePressedEvent event)
	{
		isRunning = false;
	}

	void drawOverlay()
	{
		vec2 winSize = graphics.window.size;
		vec2 center = ivec2(winSize / 2);

		//enum float thickness = 1;
		//enum float cross_size = 20;
		//vec2 hor_size = vec2(cross_size, thickness);
		//vec2 vert_size = vec2(thickness, cross_size);

		vec2 box_size = vec2(6, 6);

		graphics.overlayBatch.putRect(center - box_size/2, box_size, Colors.white, false);
	}
}
