/**
Copyright: Copyright (c) 2014-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.client.app;

import std.experimental.logger;
import std.string : format;

import anchovy.graphics.windows.glfwwindow;
import anchovy.gui;
import anchovy.gui.application.application;

import plugin;
import plugin.pluginmanager;

import voxelman.config;
import voxelman.storage.chunk;
import voxelman.storage.utils;
import voxelman.events;

import voxelman.plugins.eventdispatcherplugin;
import voxelman.plugins.graphicsplugin;
import voxelman.client.clientplugin;


//version = manualGC;
version(manualGC) import core.memory;

alias BaseApplication = Application!GlfwWindow;



final class ClientApp : BaseApplication
{
private:
	bool mouseLocked;
	bool autoMove;

	Widget debugInfo;

	PluginManager pluginman = new PluginManager;
	EventDispatcherPlugin evdispatcher = new EventDispatcherPlugin;
	ClientPlugin clientPlugin;
	GraphicsPlugin graphics = new GraphicsPlugin;

public:
	this(uvec2 windowSize, string caption)
	{
		super(windowSize, caption);
		graphics.windowSize = windowSize;
		clientPlugin = new ClientPlugin(window);
	}

	void addHideHandler(string frameId)
	{
		auto frame = context.getWidgetById(frameId);
		Widget closeButton = frame["subwidgets"].get!(Widget[string])["close"];
		closeButton.addEventHandler(delegate bool(Widget widget, PointerClickEvent event){
			frame["isVisible"] = false;
			return true;
		});
	}

	void setupFrameShowButton(string buttonId, string frameId)
	{
		auto frame = context.getWidgetById(frameId);
		context.getWidgetById(buttonId).addEventHandler(delegate bool(Widget widget, PointerClickEvent event){
			frame["isVisible"] = true;
			return true;
		});
	}

	alias init = BaseApplication.init;

	override void init(in string[] args)
	{
		super.init(args);
	}

	override void run(in string[] args)
	{
		import std.datetime : TickDuration, Clock, usecs;
		import core.thread : Thread;

		version(manualGC) GC.disable;

		pluginman.registerPlugin(clientPlugin);
		pluginman.registerPlugin(evdispatcher);
		pluginman.registerPlugin(graphics);

		init(args);
		load(args);

		info("Loading plugins");
		pluginman.initPlugins();

		TickDuration lastTime = Clock.currAppTick;
		TickDuration newTime = TickDuration.from!"seconds"(0);

		while(isRunning)
		{
			newTime = Clock.currAppTick;
			double delta = (newTime - lastTime).usecs / 1_000_000.0;
			lastTime = newTime;

			update(delta);
			draw();

			version(manualGC) GC.collect();

			// time used in frame
			delta = (lastTime - Clock.currAppTick).usecs / 1_000_000.0;
			fpsHelper.sleepAfterFrame(delta);
		}

		evdispatcher.postEvent(new GameStopEvent);
		unload();

		window.releaseWindow;
	}

	override void load(in string[] args)
	{
		info("---------------------- System info ----------------------");
		foreach(item; getHardwareInfo())
			info(item);
		info("---------------------------------------------------------\n");

		fpsHelper.limitFps = false;

		// Setup rendering
		clearColor = Color(115,200,169);
		renderer.setClearColor(clearColor);

		// Bind events
		aggregator.window.windowResized.connect(&windowResized);
		aggregator.window.keyReleased.connect(&keyReleased);
		aggregator.window.mouseReleased.connect(&mouseReleased);

		// ----------------------------- Creating widgets -----------------------------
		templateManager.parseFile("voxelman.sdl");

		auto mainLayer = context.createWidget("mainLayer");
		context.addRoot(mainLayer);

		auto frameLayer = context.createWidget("frameLayer");
		context.addRoot(frameLayer);

		// Frames
		addHideHandler("infoFrame");
		addHideHandler("settingsFrame");

		setupFrameShowButton("showInfo", "infoFrame");
		setupFrameShowButton("showSettings", "settingsFrame");

		//Buttons
		context.getWidgetById("stopServer").addEventHandler(&onStopServer);

		debugInfo = context.getWidgetById("debugInfo");
		foreach(i; 0..12) context.createWidget("label", debugInfo);

		info("\n----------------------------- Load end -----------------------------\n");
	}

	bool onStopServer(Widget widget, PointerClickEvent event)
	{
		clientPlugin.sendMessage("/stop");
		return true;
	}

	override void unload()
	{
		clientPlugin.unload();
	}

	ulong lastFrameLoadedChunks = 0;
	override void update(double dt)
	{
		evdispatcher.postEvent(new PreUpdateEvent(dt));
		window.processEvents();

		fpsHelper.update(dt);
		updateStats();

		timerManager.updateTimers(window.elapsedTime);
		context.update(dt);
		updateController(dt);

		evdispatcher.postEvent(new UpdateEvent(dt));

		printDebug();
		clientPlugin.stats.resetCounters();

		evdispatcher.postEvent(new PostUpdateEvent(dt));
	}

	void updateStats()
	{
		clientPlugin.stats.fps = fpsHelper.fps;
		clientPlugin.stats.totalLoadedChunks = clientPlugin.chunkMan.totalLoadedChunks;
	}

	void printDebug()
	{
		// Print debug info
		auto lines = debugInfo.getPropertyAs!("children", Widget[]);
		string[] statStrings = clientPlugin.stats.getFormattedOutput();

		lines[ 0]["text"] = statStrings[0].to!dstring;
		lines[ 1]["text"] = statStrings[1].to!dstring;

		lines[ 2]["text"] = statStrings[2].to!dstring;
		lines[ 3]["text"] = statStrings[3].to!dstring;
		clientPlugin.stats.lastFrameLoadedChunks = clientPlugin.stats.totalLoadedChunks;

		lines[ 4]["text"] = statStrings[4].to!dstring;
		lines[ 5]["text"] = statStrings[5].to!dstring;

		vec3 pos = graphics.camera.position;
		lines[ 6]["text"] = format("Pos: X %.2f, Y %.2f, Z %.2f",
			pos.x, pos.y, pos.z).to!dstring;

		ivec3 chunkPos = clientPlugin.chunkMan.observerPosition;
		ivec3 regionPos = calcRegionPos(chunkPos);
		ivec3 localChunkCoords = calcRegionLocalPos(chunkPos);
		lines[ 7]["text"] = format("C: %s R: %s L: %s",
			chunkPos, regionPos, localChunkCoords).to!dstring;

		vec3 target = graphics.camera.target;
		vec2 heading = graphics.camera.heading;
		lines[ 8]["text"] = format("Heading: %.2f %.2f Target: X %.2f, Y %.2f, Z %.2f",
			heading.x, heading.y, target.x, target.y, target.z).to!dstring;
		lines[ 9]["text"] = format("Chunks to remove: %s",
			clientPlugin.chunkMan.removeQueue.length).to!dstring;
		//lines[ 10]["text"] = format("Chunks to load: %s", clientPlugin.chunkMan.numLoadChunkTasks).to!dstring;
		lines[ 11]["text"] = format("Chunks to mesh: %s", clientPlugin.chunkMan.chunkMeshMan.numMeshChunkTasks).to!dstring;
	}

	void windowResized(uvec2 newSize)
	{
		graphics.windowSize = newSize;
		graphics.camera.aspect = cast(float)graphics.windowSize.x/graphics.windowSize.y;
	}

	override void draw()
	{
		guiRenderer.setClientArea(Rect(0, 0, graphics.windowSize.x, graphics.windowSize.y));
		glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT);

		renderer.disableAlphaBlending();
		evdispatcher.postEvent(new Draw1Event(renderer));
		renderer.enableAlphaBlending();

		evdispatcher.postEvent(new Draw2Event(renderer));

		context.eventDispatcher.draw();

		window.swapBuffers();
	}

	void updateController(double dt)
	{
		if(mouseLocked)
		{
			ivec2 mousePos = window.mousePosition;
			mousePos -= cast(ivec2)(graphics.windowSize) / 2;

			// scale, so up and left is positive, as rotation is anti-clockwise
			// and coordinate system is right-hand and -z if forward
			mousePos *= -1;

			if(mousePos.x !=0 || mousePos.y !=0)
			{
				graphics.camera.rotate(vec2(mousePos));
			}
			window.mousePosition = cast(ivec2)(graphics.windowSize) / 2;

			uint cameraSpeed = 10;
			vec3 posDelta = vec3(0,0,0);
			if(window.isKeyPressed(KeyCode.KEY_LEFT_SHIFT)) cameraSpeed = 60;

			if(window.isKeyPressed(KeyCode.KEY_D)) posDelta.x = 1;
			else if(window.isKeyPressed(KeyCode.KEY_A)) posDelta.x = -1;

			if(window.isKeyPressed(KeyCode.KEY_W)) posDelta.z = 1;
			else if(window.isKeyPressed(KeyCode.KEY_S)) posDelta.z = -1;

			if(window.isKeyPressed(KeyCode.KEY_SPACE)) posDelta.y = 1;
			else if(window.isKeyPressed(GLFW_KEY_LEFT_CONTROL)) posDelta.y = -1;

			if (posDelta != vec3(0))
			{
				posDelta.normalize();
				posDelta *= cameraSpeed * dt;
				graphics.camera.moveAxis(posDelta);
			}
		}
		// TODO: remove after bug is found
		else if (autoMove)
		{
			// Automoving
			graphics.camera.moveAxis(vec3(0,0,20)*dt);
		}
	}

	void keyReleased(uint keyCode)
	{
		switch(keyCode)
		{
			case KeyCode.KEY_Q: mouseLocked = !mouseLocked;
				if (mouseLocked)
					window.mousePosition = cast(ivec2)(graphics.windowSize) / 2;
				break;
			case KeyCode.KEY_P: graphics.camera.printVectors; break;
			//case KeyCode.KEY_I:

			//	chunkMan
			//	.regionStorage
			//	.getChunkStoreInfo(chunkMan.observerPosition)
			//	.writeln("\n");
			//	break;
			case KeyCode.KEY_M:
				break;
			case KeyCode.KEY_U:
				clientPlugin.doUpdateObserverPosition = !clientPlugin.doUpdateObserverPosition; break;
			case KeyCode.KEY_C: clientPlugin.isCullingEnabled = !clientPlugin.isCullingEnabled; break;
			case KeyCode.KEY_R: graphics.resetCamera(); break;
			case KeyCode.KEY_F4: clientPlugin.sendMessage("/stop"); break;
			case KeyCode.KEY_LEFT_BRACKET: clientPlugin.decViewRadius(); break;
			case KeyCode.KEY_RIGHT_BRACKET: clientPlugin.incViewRadius(); break;

			default: break;
		}
	}

	void mouseReleased(uint mouseButton)
	{
		if (mouseLocked)
		switch(mouseButton)
		{
			// left button
			case PointerButton.PB_1:
				clientPlugin.placeBlock(1);
				break;
			case PointerButton.PB_2:
				clientPlugin.placeBlock(2);
				break;
			default:break;
		}
	}

	override void closePressed()
	{
		isRunning = false;
	}
}
