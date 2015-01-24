/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.client.app;

import std.stdio : writeln;
import std.string : format;

import dlib.math.matrix;
import dlib.math.affine;

import anchovy.graphics.windows.glfwwindow;
import anchovy.gui;
import anchovy.gui.application.application;

import modular;
import modular.modulemanager;

import voxelman.config;
import voxelman.chunk;
import voxelman.chunkman;
import voxelman.utils.fpscontroller;
import voxelman.utils.camera;

import voxelman.modules.eventdispatchermodule;

class GameStopEvent : GameEvent {}

class UpdateEvent : GameEvent {
	this(double dt)
	{
		deltaTime = dt;
	}
	double deltaTime;
}
class PreUpdateEvent : UpdateEvent {
	this(double dt) {
		super(dt);
	}
}
class PostUpdateEvent : UpdateEvent {
	this(double dt) {
		super(dt);
	}
}

__gshared ChunkMan chunkMan;

//version = manualGC;
version(manualGC) import core.memory;

alias BaseApplication = Application!GlfwWindow;

class ClientApp : BaseApplication, IModule
{
private:
	uvec3 viewSize;
	ulong chunksVisible;
	ulong chunksRendered;
	ulong vertsRendered;
	ulong trisRendered;

	ShaderProgram chunkShader;
	GLuint modelLoc, viewLoc, projectionLoc;

	FpsController fpsController;
	bool mouseLocked;
	bool isCullingEnabled = true;
	bool autoMove;
	bool doUpdateObserverPosition = true;

	Widget debugInfo;

	ModuleManager moduleman = new ModuleManager;
	EventDispatcherModule evdispatcher = new EventDispatcherModule;

public:
	// IModule stuff
	override string name() @property { return "ClientApp"; }
	override string semver() @property { return "1.0.0"; }
	override void preInit() { }
	override void init(IModuleManager moduleman) { }
	override void postInit() { }

	this(uvec2 windowSize, string caption)
	{
		super(windowSize, caption);
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

		moduleman.registerModule(this);
		moduleman.registerModule(evdispatcher);

		init(args);
		load(args);

		writeln("Loading modules");
		moduleman.initModules();
		writeln;


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
		writeln("---------------------- System info ----------------------");
		foreach(item; getHardwareInfo())
			writeln(item);
		writeln("---------------------------------------------------------\n");

		fpsHelper.limitFps = false;

		// Setup rendering

		clearColor = Color(115,200,169);
		renderer.setClearColor(clearColor);

		fpsController.move(startPos);
		fpsController.camera.sensivity = 0.4;
		fpsController.camera.updateProjection();

		fpsController.camera.aspect = cast(float)window.size.x/window.size.y;
		fpsController.camera.updateProjection();

		// Setup shaders

		string vShader = cast(string)read("perspective.vert");
		string fShader = cast(string)read("colored.frag");
		chunkShader = new ShaderProgram(vShader, fShader);

		if(!chunkShader.compile())
		{
			writeln(chunkShader.errorLog);
		}
		else
		{
			writeln("Shaders compiled successfully");
		}

		chunkShader.bind;
			modelLoc = glGetUniformLocation( chunkShader.program, "model" );//model transformation
			viewLoc = glGetUniformLocation( chunkShader.program, "view" );//camera trandformation
			projectionLoc = glGetUniformLocation( chunkShader.program, "projection" );//perspective	

			glUniformMatrix4fv(modelLoc, 1, GL_FALSE, cast(const float*)Matrix4f.identity.arrayof);
			glUniformMatrix4fv(viewLoc, 1, GL_FALSE, cast(const float*)fpsController.cameraMatrix);
			glUniformMatrix4fv(projectionLoc, 1, GL_FALSE, cast(const float*)fpsController.camera.perspective.arrayof);
		chunkShader.unbind;

		// Bind events

		aggregator.window.windowResized.connect(&windowResized);
		aggregator.window.keyReleased.connect(&keyReleased);

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

		debugInfo = context.getWidgetById("debugInfo");
		foreach(i; 0..12) context.createWidget("label", debugInfo);

		writeln("\n----------------------------- Load end -----------------------------\n");

		// ----------------------------- init chunks ---------------------------

		chunkMan.init();
		chunkMan.updateObserverPosition(fpsController.camera.position);
	}

	override void unload()
	{
		chunkMan.stop();
	}

	ulong lastFrameLoadedChunks = 0;
	override void update(double dt)
	{
		evdispatcher.postEvent(new PreUpdateEvent(dt));
		window.processEvents();

		fpsHelper.update(dt);
		printDebug();
		timerManager.updateTimers(window.elapsedTime);
		context.update(dt);

		updateController(dt);
		chunkMan.update();
		if (doUpdateObserverPosition)
			chunkMan.updateObserverPosition(fpsController.camera.position);
		evdispatcher.postEvent(new UpdateEvent(dt));
		evdispatcher.postEvent(new PostUpdateEvent(dt));
	}

	void printDebug()
	{
		// Print debug info
		auto lines = debugInfo.getPropertyAs!("children", Widget[]);

		lines[ 0]["text"] = format("FPS: %s", fpsHelper.fps).to!dstring;
		lines[ 1]["text"] = format("Chunks visible/rendered %s/%s %.0f%%",
			chunksVisible, chunksRendered,
			chunksVisible ? cast(float)chunksRendered/chunksVisible*100 : 0)
			.to!dstring;
		chunksVisible = 0;
		chunksRendered = 0;
		
		ulong chunksLoaded = chunkMan.totalLoadedChunks;
		lines[ 2]["text"] = format("Chunks per frame loaded: %s",
			chunksLoaded - lastFrameLoadedChunks).to!dstring;
		lines[ 3]["text"] = format("Chunks total loaded: %s",
			chunksLoaded).to!dstring;
		lastFrameLoadedChunks = chunksLoaded;

		lines[ 4]["text"] = format("Vertexes %s", vertsRendered).to!dstring;
		vertsRendered = 0;
		lines[ 5]["text"] = format("Triangles %s", trisRendered).to!dstring;
		trisRendered = 0;

		vec3 pos = fpsController.camera.position;
		lines[ 6]["text"] = format("Pos: X %.2f, Y %.2f, Z %.2f",
			pos.x, pos.y, pos.z).to!dstring;

		ivec3 chunkPos = chunkMan.observerPosition;
		ivec3 regionPos = calcRegionPos(chunkPos);
		ivec3 localChunkCoords = calcRegionLocalPos(chunkPos);
		lines[ 7]["text"] = format("C: %s R: %s L: %s",
			chunkPos, regionPos, localChunkCoords).to!dstring;

		vec3 target = fpsController.camera.target;
		lines[ 8]["text"] = format("Target: X %.2f, Y %.2f, Z %.2f",
			target.x, target.y, target.z).to!dstring;
		lines[ 9]["text"] = format("Chunks to remove: %s", chunkMan.numChunksToRemove).to!dstring;
		lines[ 10]["text"] = format("Chunks to load: %s", chunkMan.numLoadChunkTasks).to!dstring;
		lines[ 11]["text"] = format("Chunks to mesh: %s", chunkMan.numMeshChunkTasks).to!dstring;
	}

	void windowResized(uvec2 newSize)
	{
		fpsController.camera.aspect = cast(float)newSize.x/newSize.y;
		fpsController.camera.updateProjection();
	}

	override void draw()
	{
		guiRenderer.setClientArea(Rect(0, 0, window.size.x, window.size.y));
		glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT);

		renderer.disableAlphaBlending();
		drawScene();
		renderer.enableAlphaBlending();

		context.eventDispatcher.draw();

		window.swapBuffers();
	}

	void drawScene()
	{
		glEnable(GL_DEPTH_TEST);
		
		chunkShader.bind;
		glUniformMatrix4fv(viewLoc, 1, GL_FALSE,
			fpsController.cameraMatrix);
		glUniformMatrix4fv(projectionLoc, 1, GL_FALSE,
			cast(const float*)fpsController.camera.perspective.arrayof);

		import dlib.geometry.aabb;
		import dlib.geometry.frustum;
		Matrix4f vp = fpsController.camera.perspective * fpsController.cameraToClipMatrix;
		Frustum frustum;
		frustum.fromMVP(vp);

		Matrix4f modelMatrix;
		foreach(Chunk* c; chunkMan.visibleChunks)
		{
			++chunksVisible;

			if (isCullingEnabled)
			{
				// Frustum culling
				ivec3 ivecMin = c.coord * CHUNK_SIZE;
				vec3 vecMin = vec3(ivecMin.x, ivecMin.y, ivecMin.z);
				vec3 vecMax = vecMin + CHUNK_SIZE;
				AABB aabb = boxFromMinMaxPoints(vecMin, vecMax);
				auto intersects = frustum.intersectsAABB(aabb);
				if (!intersects) continue;
			}

			modelMatrix = translationMatrix!float(c.mesh.position);
			glUniformMatrix4fv(modelLoc, 1, GL_FALSE, cast(const float*)modelMatrix.arrayof);
			
			c.mesh.bind;
			c.mesh.render;

			++chunksRendered;
			vertsRendered += c.mesh.numVertexes;
			trisRendered += c.mesh.numTris;
		}
		chunkShader.unbind;

		glDisable(GL_DEPTH_TEST);
		
		renderer.setColor(Color(0,0,0,1));
		renderer.drawRect(Rect(window.size.x/2-7, window.size.y/2-1, 14, 2));
		renderer.drawRect(Rect(window.size.x/2-1, window.size.y/2-7, 2, 14));
	}

	void updateController(double dt)
	{
		if(mouseLocked)
		{
			ivec2 mousePos = window.mousePosition;
			mousePos -= cast(ivec2)(window.size) / 2;

			if(mousePos.x !=0 || mousePos.y !=0)
			{
				fpsController.rotateHor(mousePos.x);
				fpsController.rotateVert(mousePos.y);
			}
			window.mousePosition = cast(ivec2)(window.size) / 2;

			uint cameraSpeed = 30;
			vec3 posDelta = vec3(0,0,0);
			if(window.isKeyPressed(KeyCode.KEY_LEFT_SHIFT)) cameraSpeed = 80;

			if(window.isKeyPressed(KeyCode.KEY_D)) posDelta.x = 1;
			else if(window.isKeyPressed(KeyCode.KEY_A)) posDelta.x = -1;

			if(window.isKeyPressed(KeyCode.KEY_W)) posDelta.z = 1;
			else if(window.isKeyPressed(KeyCode.KEY_S)) posDelta.z = -1;

			if(window.isKeyPressed(GLFW_KEY_SPACE)) posDelta.y = 1;
			else if(window.isKeyPressed(GLFW_KEY_LEFT_CONTROL)) posDelta.y = -1;

			if (posDelta != vec3(0))
			{
				posDelta *= cameraSpeed * dt;
				fpsController.moveAxis(posDelta);
			}
		}
		// TODO: remove after bug is found
		else if (autoMove)
		{
			// Automoving
			fpsController.moveAxis(vec3(0,0,20)*dt);
		}
	}

	void keyReleased(uint keyCode)
	{
		switch(keyCode)
		{
			case KeyCode.KEY_Q: mouseLocked = !mouseLocked;
				if (mouseLocked)
					window.mousePosition = cast(ivec2)(window.size) / 2;
				break;
			case KeyCode.KEY_P: fpsController.printVectors; break;
			//case KeyCode.KEY_I:

			//	chunkMan
			//	.regionStorage
			//	.getChunkStoreInfo(chunkMan.observerPosition)
			//	.writeln("\n");
			//	break;
			case KeyCode.KEY_M:

				break;
			case KeyCode.KEY_U: doUpdateObserverPosition = !doUpdateObserverPosition; break;
			case KeyCode.KEY_C: isCullingEnabled = !isCullingEnabled; break;
			case KeyCode.KEY_R: resetCamera(); break;
			default: break;
		}
	}

	void resetCamera()
	{
		fpsController.camera.position=vec3(0,0,0);
		fpsController.camera.target=vec3(0,0,1);
		fpsController.angleHor = 0;
		fpsController.angleVert = 0;
		fpsController.update();
	}

	override void closePressed()
	{
		isRunning = false;
	}
}