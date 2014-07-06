/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.app;

import std.stdio : writeln;

import anchovy.graphics.windows.glfwwindow;
import anchovy.gui;
import anchovy.gui.application.application;

class TestApplication : Application!GlfwWindow
{
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

		fpsHelper.limitFps = false;

		clearColor = Color(0,0,0);
		renderer.setClearColor(clearColor);

		// ----------------------------- Creating widgets -----------------------------
		templateManager.parseFile("voxelman.sdl");

		auto mainLayer = context.createWidget("mainLayer");
		context.addRoot(mainLayer);

		auto frameLayer = context.createWidget("frameLayer");
		context.addRoot(frameLayer);

		// FPS printing
		auto fpsLabel = context.getWidgetById("fpsLabel");
		auto fpsSlot = (FpsHelper* helper){fpsLabel["text"] = "FPS: "~to!string(helper.fps);};
		fpsHelper.fpsUpdated.connect(fpsSlot);

		// Frames
		addHideHandler("infoFrame");
		addHideHandler("settingsFrame");

		setupFrameShowButton("showInfo", "infoFrame");
		setupFrameShowButton("showSettings", "settingsFrame");

		writeln("\n----------------------------- Load end -----------------------------\n");
	}

	override void draw()
	{
		guiRenderer.setClientArea(Rect(0, 0, window.size.x, window.size.y));
		glClear(GL_COLOR_BUFFER_BIT);

		drawScene();

		context.eventDispatcher.draw();

		window.swapBuffers();
	}

	void drawScene()
	{

	}

	override void closePressed()
	{
		isRunning = false;
	}
}