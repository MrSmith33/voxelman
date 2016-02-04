/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.client.plugin;

import core.thread : thread_joinAll;
import core.time;
import std.experimental.logger;

import dlib.math.vector;
import dlib.math.matrix : Matrix4f;
import dlib.math.affine : translationMatrix;
import derelict.enet.enet;
import derelict.opengl3.gl3;
import derelict.imgui.imgui;

import anchovy.fpshelper;

import netlib;
import pluginlib;
import pluginlib.pluginmanager;

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

import voxelman.storage.chunk;
import voxelman.storage.coordinates;
import voxelman.storage.utils;
import voxelman.storage.worldaccess;
import voxelman.utils.math;
import voxelman.utils.textformatter;

import voxelman.client.appstatistics;
import voxelman.client.console;

//version = manualGC;
version(manualGC) import core.memory;

shared static this()
{
	auto c = new ClientPlugin;
	pluginRegistry.regClientPlugin(c);
	pluginRegistry.regClientMain(&c.run);
}

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
	PluginManager pluginman;

	// Plugins
	EventDispatcherPlugin evDispatcher;
	GraphicsPlugin graphics;
	GuiPlugin guiPlugin;
	CommandPluginClient commandPlugin;
	ClientWorld clientWorld;
	NetClientPlugin connection;
	Debugger dbg;

public:
	AppStatistics stats;
	Console console;

	// Client data
	bool isRunning = false;
	bool mouseLocked;

	double delta;
	Duration frameTime;
	ConfigOption maxFpsOpt;
	bool limitFps = true;
	FpsHelper fpsHelper;

	// Graphics stuff
	bool isCullingEnabled = true;
	bool isConsoleShown = false;

	// IPlugin stuff
	mixin IdAndSemverFrom!(voxelman.client.plugininfo);

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		ConfigManager config = resmanRegistry.getResourceManager!ConfigManager;
		maxFpsOpt = config.registerOption!uint("max_fps", true);

		dbg = resmanRegistry.getResourceManager!Debugger;

		KeyBindingManager keyBindingMan = resmanRegistry.getResourceManager!KeyBindingManager;
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_Q, "key.lockMouse", null, &onLockMouse));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_C, "key.toggleCulling", null, &onToggleCulling));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_GRAVE_ACCENT, "key.toggle_console", null, &onConsoleToggleKey));
	}

	override void preInit()
	{
		fpsHelper.maxFps = maxFpsOpt.get!uint;
		if (fpsHelper.maxFps == 0) fpsHelper.limitFps = false;
		console.init();
	}

	override void init(IPluginManager pluginman)
	{
		clientWorld = pluginman.getPlugin!ClientWorld;
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;

		graphics = pluginman.getPlugin!GraphicsPlugin;
		guiPlugin = pluginman.getPlugin!GuiPlugin;

		evDispatcher.subscribeToEvent(&onPreUpdateEvent);
		evDispatcher.subscribeToEvent(&onPostUpdateEvent);
		evDispatcher.subscribeToEvent(&drawScene);
		evDispatcher.subscribeToEvent(&drawOverlay);
		evDispatcher.subscribeToEvent(&onClosePressedEvent);

		commandPlugin = pluginman.getPlugin!CommandPluginClient;
		console.messageWindow.messageHandler = &onConsoleCommand;

		connection = pluginman.getPlugin!NetClientPlugin;
	}

	override void postInit() {}

	void printDebug()
	{
		igSetNextWindowSize(ImVec2(400, 300), ImGuiSetCond_FirstUseEver);
		igSetNextWindowPos(ImVec2(0, 0), ImGuiSetCond_FirstUseEver);
		igBegin("Debug");
		with(stats) {
			igTextf("FPS: %s", fps); igSameLine();

			int fpsLimitVal = maxFpsOpt.get!uint;
			igPushItemWidth(60);
			//igInputInt("limit", &fpsLimitVal, 5, 20, 0);
			igSliderInt(limitFps ? "limited##limit" : "unlimited##limit", &fpsLimitVal, 0, 240, null);
			igPopItemWidth();
			maxFpsOpt.set!uint(fpsLimitVal);
			updateFrameTime();

			igTextf("Chunks visible/rendered %s/%s %.0f%%",
				chunksVisible, chunksRendered,
				chunksVisible ? cast(float)chunksRendered/chunksVisible*100 : 0);
			igTextf("Chunks per frame loaded: %s",
				totalLoadedChunks - lastFrameLoadedChunks);
			igTextf("Chunks total loaded: %s",
				totalLoadedChunks);
			igTextf("Vertexes %s", vertsRendered);
			igTextf("Triangles %s", trisRendered);
			vec3 pos = graphics.camera.position;
			igTextf("Pos: X %.2f, Y %.2f, Z %.2f", pos.x, pos.y, pos.z);
		}

		ChunkWorldPos chunkPos = clientWorld.chunkMan.observerPosition;
		auto regionPos = RegionWorldPos(chunkPos);
		auto localChunkPosition = ChunkRegionPos(chunkPos);
		igTextf("Chunk: %s %s %s", chunkPos.x, chunkPos.y, chunkPos.z);

		vec3 target = graphics.camera.target;
		vec2 heading = graphics.camera.heading;
		igTextf("Heading: %.2f %.2f", heading.x, heading.y);
		igTextf("Target: X %.2f, Y %.2f, Z %.2f", target.x, target.y, target.z);
		with(clientWorld.chunkMan) {
			igTextf("Chunks to remove: %s", removeQueue.length);
			igTextf("Chunks to mesh: %s", chunkMeshMan.numMeshChunkTasks);
			igTextf("Meshed/Meshes %s/%s", chunkMeshMan.totalMeshedChunks, chunkMeshMan.totalMeshes);
			igTextf("View radius: %s", viewRadius);
		}
		igEnd();
	}

	this()
	{
		pluginman = new PluginManager;
	}

	void load(string[] args)
	{
		// register all plugins and managers
		import voxelman.pluginlib.plugininforeader : filterEnabledPlugins;
		foreach(p; pluginRegistry.clientPlugins.byValue.filterEnabledPlugins(args))
		{
			pluginman.registerPlugin(p);
		}

		// Actual loading sequence
		pluginman.initPlugins();
	}

	void run(string[] args)
	{
		import std.datetime : MonoTime, Duration, usecs, dur;
		import core.thread : Thread;

		version(manualGC) GC.disable;

		load(args);
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

				version(manualGC) GC.collect();

				if (limitFps) {
					Duration updateTime = MonoTime.currTime - newTime;
					Duration sleepTime = frameTime - updateTime;
					if (sleepTime > Duration.zero)
						Thread.sleep(sleepTime);
				}

				++frame;
		}
		evDispatcher.postEvent(GameStopEvent());
	}

	void updateFrameTime()
	{
		uint maxFps = maxFpsOpt.get!uint;
		if (maxFps == 0) {
			limitFps = false;
			frameTime = Duration.zero;
			return;
		}

		limitFps = true;
		frameTime = (1_000_000 / maxFpsOpt.get!uint).usecs;
	}

	void onPreUpdateEvent(ref PreUpdateEvent event)
	{
		fpsHelper.update(event.deltaTime);
	}

	void onPostUpdateEvent(ref PostUpdateEvent event)
	{
		stats.fps = fpsHelper.fps;
		stats.totalLoadedChunks = clientWorld.chunkMan.totalLoadedChunks;

		printDebug();
		stats.resetCounters();
		if (isConsoleShown)
			console.draw();
		dbg.logVar("delta, ms", delta*1000.0, 256);
	}

	void onConsoleCommand(string command)
	{
		infof("Executing command '%s'", command);
		ExecResult res = commandPlugin.execute(command, ClientId(0));

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

	void onLockMouse(string)
	{
		mouseLocked = !mouseLocked;
		if (mouseLocked)
			guiPlugin.window.mousePosition = cast(ivec2)(guiPlugin.window.size) / 2;
	}

	void onToggleCulling(string)
	{
		isCullingEnabled = !isCullingEnabled;
	}

	void drawScene(ref Render1Event event)
	{
		graphics.chunkShader.bind;
		glUniformMatrix4fv(graphics.viewLoc, 1, GL_FALSE,
			graphics.camera.cameraMatrix);
		glUniformMatrix4fv(graphics.projectionLoc, 1, GL_FALSE,
			cast(const float*)graphics.camera.perspective.arrayof);

		import dlib.geometry.aabb;
		import dlib.geometry.frustum;
		Matrix4f vp = graphics.camera.perspective * graphics.camera.cameraToClipMatrix;
		Frustum frustum;
		frustum.fromMVP(vp);

		Matrix4f modelMatrix;
		foreach(mesh; clientWorld.chunkMan.chunkMeshMan.visibleChunks.byValue)
		{
			++stats.chunksVisible;
			if (isCullingEnabled) // Frustum culling
			{
				vec3 vecMin = mesh.position;
				vec3 vecMax = vecMin + CHUNK_SIZE;
				AABB aabb = boxFromMinMaxPoints(vecMin, vecMax);
				auto intersects = frustum.intersectsAABB(aabb);
				if (!intersects) continue;
			}

			modelMatrix = translationMatrix!float(mesh.position);
			glUniformMatrix4fv(graphics.modelLoc, 1, GL_FALSE, cast(const float*)modelMatrix.arrayof);

			mesh.bind;
			mesh.render;

			++stats.chunksRendered;
			stats.vertsRendered += mesh.numVertexes;
			stats.trisRendered += mesh.numTris;
		}

		glUniformMatrix4fv(graphics.modelLoc, 1, GL_FALSE, cast(const float*)Matrix4f.identity.arrayof);
		graphics.chunkShader.unbind;
	}

	void drawOverlay(ref Render2Event event)
	{
		//event.renderer.setColor(Color(0,0,0,1));
		//event.renderer.fillRect(Rect(guiPlugin.window.size.x/2-7, guiPlugin.window.size.y/2-1, 14, 2));
		//event.renderer.fillRect(Rect(guiPlugin.window.size.x/2-1, guiPlugin.window.size.y/2-7, 2, 14));
	}
}
