/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.app;

import std.stdio : writeln;
import std.string : format;

import dlib.math.matrix;
import dlib.math.affine;

import anchovy.graphics.windows.glfwwindow;
import anchovy.gui;
import anchovy.gui.application.application;
import anchovy.gui.databinding.list;

import voxelman.fpscontroller;
import voxelman.camera;

import voxelman.chunk;
import voxelman.chunkman;

__gshared ChunkMan chunkMan;

//version = manualGC;
version(manualGC) import core.memory;

class VoxelApplication : Application!GlfwWindow
{
	uvec3 viewSize;
	ulong chunksRendered;
	ulong vertsRendered;
	ulong trisRendered;

	ShaderProgram chunkShader;
	GLuint modelLoc, viewLoc, projectionLoc;

	FpsController fpsController;
	FpsController secondFpsController;
	bool mouseLocked;
	bool autoMove;
	bool doUpdateObserverPosition = true;

	Widget debugInfo;

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

	override void load(in string[] args)
	{
		writeln("---------------------- System info ----------------------");
		foreach(item; getHardwareInfo())
			writeln(item);
		writeln("---------------------------------------------------------\n");

		version(manualGC) GC.disable;

		fpsHelper.limitFps = false;

		// Setup rendering

		clearColor = Color(115,200,169);
		renderer.setClearColor(clearColor);

		fpsController.move(vec3(0, 200, 0));
		fpsController.camera.sensivity = 0.4;
		fpsController.camera.updateProjection();
		secondFpsController.camera.updateProjection();

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
		foreach(i; 0..11) context.createWidget("label", debugInfo);

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
		stdout.flush;
		fpsHelper.update(dt);

		printDebug();
		timerManager.updateTimers(window.elapsedTime);
		context.update(dt);

		updateController(dt);
		chunkMan.update();
		if (doUpdateObserverPosition)
			chunkMan.updateObserverPosition(fpsController.camera.position);
	}

	void printDebug()
	{
		// Print debug info
		auto lines = debugInfo.getPropertyAs!("children", Widget[]);

		lines[ 0]["text"] = format("FPS: %s", fpsHelper.fps).to!dstring;
		lines[ 1]["text"] = format("Chunks rendered %s", chunksRendered).to!dstring;
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
		lines[ 6]["text"] = format("Position: X %.2f, Y %.2f, Z %.2f",
			pos.x, pos.y, pos.z).to!dstring;

		vec3 target = fpsController.camera.target;
		lines[ 7]["text"] = format("Target: X %.2f, Y %.2f, Z %.2f",
			target.x, target.y, target.z).to!dstring;
		lines[ 8]["text"] = format("Chunks to remove: %s", chunkMan.numChunksToRemove).to!dstring;
		lines[ 9]["text"] = format("Chunks to load: %s", chunkMan.numLoadChunkTasks).to!dstring;
		lines[ 10]["text"] = format("Chunks to mesh: %s", chunkMan.numMeshChunkTasks).to!dstring;
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
		version(manualGC) GC.collect();
	}

	void drawScene()
	{
		glEnable(GL_DEPTH_TEST);
		
		chunkShader.bind;
		glUniformMatrix4fv(viewLoc, 1, GL_FALSE,
			fpsController.cameraMatrix);
		glUniformMatrix4fv(projectionLoc, 1, GL_FALSE,
			cast(const float*)fpsController.camera.perspective.arrayof);

		Matrix4f vp = secondFpsController.camera.perspective * secondFpsController.cameraToClipMatrix;
		secondFpsController.camera.updateFrustum(vp);

		Matrix4f modelMatrix;
		foreach(Chunk* c; chunkMan.visibleChunks)
		{
			// Frustum culling
			svec4 svecMin = c.coord.vector * chunkSize;
			vec3 vecMin = vec3(svecMin.x, svecMin.y, svecMin.z);
			vec3 vecMax = vecMin + chunkSize;

			import dlib.geometry.frustum, dlib.geometry.aabb;
			Frustum frustum;
			frustum.fromMVP(vp);
			if (frustum.intersectsAABB(boxFromMinMaxPoints(vecMin, vecMax))) continue;

			auto test = secondFpsController.camera.frustumAABBIntersect(vecMin, vecMax);
			if (test == IntersectionResult.outside) continue;

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
			case KeyCode.KEY_I: fpsController.moveAxis(vec3(0, 0, 1)); break;
			case KeyCode.KEY_K: fpsController.moveAxis(vec3(0, 0, -1)); break;
			case KeyCode.KEY_J: fpsController.moveAxis(vec3(-1, 0, 0)); break;
			case KeyCode.KEY_L: fpsController.moveAxis(vec3(1, 0, 0)); break;
			case KeyCode.KEY_O: fpsController.moveAxis(vec3(0, 1, 0)); break;
			case KeyCode.KEY_U: doUpdateObserverPosition = !doUpdateObserverPosition; break;
			case KeyCode.KEY_T: fpsController.moveAxis(vec3(0, 0, 128)); break;
			case KeyCode.KEY_C: secondFpsController = fpsController; break;
			case KeyCode.KEY_UP: fpsController.rotateVert(-45); break;
			case KeyCode.KEY_DOWN: fpsController.rotateVert(45); break;
			case KeyCode.KEY_LEFT: fpsController.rotateHor(-45); break;
			case KeyCode.KEY_RIGHT: fpsController.rotateHor(45); break;
			case KeyCode.KEY_R: resetCamera(); break;
			default: break;
		}
	}

	void resetCamera()
	{
		fpsController.camera.position=vec3(0,0,0);
		fpsController.angleHor = 0;
		fpsController.angleVert = 0;		
		fpsController.update();
	}

	override void closePressed()
	{
		isRunning = false;
	}
}