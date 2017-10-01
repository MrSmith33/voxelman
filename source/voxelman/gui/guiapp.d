/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.gui.guiapp;

import std.stdio : writefln, writeln;
import std.datetime : MonoTime, Duration, usecs, dur;
import std.string : format;
import voxelman.container.gapbuffer;
import voxelman.graphics;
import voxelman.gui;
import voxelman.math;
import voxelman.platform;
import voxelman.text.linebuffer;
import voxelman.text.scale;
import voxelman.utils.fpshelper;

class GuiApp
{
	FpsHelper fpsHelper;
	GuiContext guictx;
	IRenderer renderer;
	IWindow window;
	RenderQueue renderQueue;
	LineBuffer debugText;

	bool isClosePressed;
	bool limitFps = true;
	int maxFps = 40;
	double updateTime = 0;
	bool showDebugInfo;

	string title;
	ivec2 windowSize;

	this(string title, ivec2 windowSize)
	{
		this.title = title;
		this.windowSize = windowSize;
	}

	void run(string[] args)
	{
		import std.datetime : MonoTime, Duration, usecs, dur;
		import core.thread : Thread;

		load(args);

		MonoTime prevTime = MonoTime.currTime;

		bool isRunning = true;

		void checkForClose()
		{
			if (isClosePressed)
				isRunning = false;
		}

		while(isRunning)
		{
			MonoTime newTime = MonoTime.currTime;
			double delta = (newTime - prevTime).total!"usecs" / 1_000_000.0;
			prevTime = newTime;

			fpsHelper.update(delta, updateTime);
			update(delta);

			Duration updateTimeDur = MonoTime.currTime - newTime;
			updateTime = updateTimeDur.total!"usecs" / 1_000_000.0;

			if (limitFps) {
				Duration targetFrameTime = (1_000_000 / maxFps).usecs;
				Duration sleepTime = targetFrameTime - updateTimeDur;
				if (sleepTime > Duration.zero)
					Thread.sleep(sleepTime);
			}

			checkForClose();
		}

		stop();
	}

	void load(string[] args)
	{
		import std.string : fromStringz;
		import voxelman.graphics.gl;

		loadOpenGL();

		window = new GlfwWindow();
		window.init(windowSize, title);

		reloadOpenGL();

		renderer = new OglRenderer(window);
		auto resourceManager = new ResourceManager(renderer);
		renderQueue = new RenderQueue(resourceManager);
		guictx = new GuiContext(&debugText);
		guictx.pointerMoved(window.mousePosition);
		guictx.style.defaultFont = renderQueue.defaultFont;

		window.mousePressed.connect(&guictx.pointerPressed);
		window.mouseReleased.connect(&guictx.pointerReleased);
		window.mouseMoved.connect(&guictx.pointerMoved);
		window.wheelScrolled.connect(&guictx.onScroll);
		window.keyPressed.connect(&guictx.onKeyPress);
		window.keyReleased.connect(&guictx.onKeyRelease);
		window.charEntered.connect(&guictx.onCharEnter);
		guictx.state.setClipboard = &window.clipboardString;
		guictx.state.getClipboard = &window.clipboardString;

		renderer.setClearColor(255, 255, 255);

		// Bind events
		window.windowResized.connect(&windowResized);
		window.closePressed.connect(&closePressed);

		guictx.style.iconMap = loadNamedSpriteSheet("icons", resourceManager.texAtlas, ivec2(16, 16));
		guictx.style.iconPlaceholder = guictx.style.iconMap["no-icon"];

		resourceManager.reuploadTexture();
	}

	void update(double delta)
	{
		window.processEvents();
		renderQueue.beginFrame();

		userPreUpdate(delta);

		guictx.state.canvasSize = renderer.framebufferSize;
		guictx.update(delta, renderQueue);
		window.setCursorIcon(guictx.state.cursorIcon);

		userPostUpdate(delta);

		if (showDebugInfo) drawDebugText();
		debugText.clear();
		renderQueue.endFrame();

		// render
		checkgl!glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT);
		renderQueue.drawFrame();
		renderer.flush();
	}

	int overlayDepth = 1000;
	void drawDebugText()
	{
		auto pos = vec2(renderer.framebufferSize.x, 0);

		auto mesherParams = renderQueue.startTextAt(pos + vec2(-5,5));
		mesherParams.depth = overlayDepth;

		mesherParams.meshText(debugText.lines.data);
		mesherParams.alignMeshedText(Alignment.max);

		renderQueue.drawRectFill(vec2(mesherParams.origin)-vec2(5,5), mesherParams.size + vec2(10,10), overlayDepth-1, Colors.white);
		renderQueue.drawRectLine(vec2(mesherParams.origin)-vec2(6,6), mesherParams.size + vec2(12,12), overlayDepth-1, Colors.black);
	}

	void userPreUpdate(double delta) {}
	void userPostUpdate(double delta) {}

	void stop()
	{
		window.releaseWindow;
	}

	void windowResized(ivec2 newSize)
	{
		renderer.setViewport(ivec2(0, 0), renderer.framebufferSize);
	}

	void closePressed()
	{
		isClosePressed = true;
	}
}

