/**
Copyright: Copyright (c) 2013-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.platform.glfwwindow;

import std.conv : to;
import std.string : toStringz, fromStringz, format;

import derelict.glfw3.glfw3;
import voxelman.graphics.gl;
import voxelman.log;
import voxelman.math;
import voxelman.platform.iwindow : IWindow, CursorIcon;
import voxelman.platform.isharedcontext;
import voxelman.platform.input : KeyCode, PointerButton;

class GlfwSharedContext : ISharedContext
{
	GLFWwindow* sharedContext;

	this(GLFWwindow* _sharedContext)
	{
		this.sharedContext = _sharedContext;
	}

	void makeCurrent()
	{
		glfwMakeContextCurrent(sharedContext);
	}
}

class GlfwWindow : IWindow
{
private:
	GLFWwindow*	glfwWindowPtr;
	static bool	glfwInited = false;
	bool isProcessingEvents = false;
	GLFWcursor*[6] cursors;

public:
	override void init(ivec2 size, in string caption, bool center = false)
	{
		if (!glfwInited)
			initGlfw();

		scope(failure) glfwTerminate();

		glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
		glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);
		glfwWindowHint(GLFW_VISIBLE, false);

		//BUG: sometimes fails in Windows 8. Maybe because of old drivers.
		glfwWindowPtr = glfwCreateWindow(size.x, size.y, toStringz(caption), null,  null);

		if (glfwWindowPtr is null)
		{
			throw new Error("Error creating GLFW3 window");
		}

		if (center) moveToCenter();

		glfwShowWindow(glfwWindowPtr);

		glfwMakeContextCurrent(glfwWindowPtr);

		glClearColor(1.0, 1.0, 1.0, 1.0);
		glViewport(0, 0, size.x, size.y);

		glfwSetWindowUserPointer(glfwWindowPtr, cast(void*)this);
		glfwSetWindowPosCallback(glfwWindowPtr, &windowposfun);
		glfwSetFramebufferSizeCallback(glfwWindowPtr, &windowsizefun);
		glfwSetWindowCloseCallback(glfwWindowPtr, &windowclosefun);
		//glfwSetWindowRefreshCallback(glfwWindowPtr, &windowrefreshfun);
		glfwSetWindowFocusCallback(glfwWindowPtr, &windowfocusfun);
		glfwSetWindowIconifyCallback(glfwWindowPtr, &windowiconifyfun);
		glfwSetMouseButtonCallback(glfwWindowPtr, &mousebuttonfun);
		glfwSetCursorPosCallback(glfwWindowPtr, &cursorposfun);
		glfwSetScrollCallback(glfwWindowPtr, &scrollfun);
		glfwSetKeyCallback(glfwWindowPtr, &keyfun);
		glfwSetCharCallback(glfwWindowPtr, &charfun);
		//glfwSetCursorEnterCallback(window, GLFWcursorenterfun cbfun);
		glfwSetWindowRefreshCallback(glfwWindowPtr, &refreshfun);

		// create standard cursors
		cursors[0] = glfwCreateStandardCursor(GLFW_ARROW_CURSOR);
		cursors[1] = glfwCreateStandardCursor(GLFW_IBEAM_CURSOR);
		cursors[2] = glfwCreateStandardCursor(GLFW_CROSSHAIR_CURSOR);
		cursors[3] = glfwCreateStandardCursor(GLFW_HAND_CURSOR);
		cursors[4] = glfwCreateStandardCursor(GLFW_HRESIZE_CURSOR);
		cursors[5] = glfwCreateStandardCursor(GLFW_VRESIZE_CURSOR);
	}

	override ISharedContext createSharedContext()
	{
		assert(glfwInited);
		assert(glfwWindowPtr);
		glfwWindowHint(GLFW_VISIBLE, false);
		GLFWwindow* sharedContext = glfwCreateWindow(100, 100, "", null, glfwWindowPtr);
		return new GlfwSharedContext(sharedContext);
	}

	override void moveToCenter()
	{
		GLFWmonitor* primaryMonitor = glfwGetPrimaryMonitor();
		ivec2 currentSize = size();
		ivec2 primPos;
		glfwGetMonitorPos(primaryMonitor, &primPos.x, &primPos.y);
		const GLFWvidmode* primMode = glfwGetVideoMode(primaryMonitor);
		ivec2 primSize = ivec2(primMode.width, primMode.height);
		ivec2 newPos = primPos + primSize/2 - currentSize/2;
		glfwSetWindowPos(glfwWindowPtr, newPos.x, newPos.y);
	}

	override void processEvents()
	{
		// prevent calling glfwPollEvents when inside window_refresh callback
		if (!isProcessingEvents)
		{
			isProcessingEvents = true;
			glfwPollEvents();
			isProcessingEvents = false;
		}
	}

	override double elapsedTime() @property //in seconds
	{
		return glfwGetTime();
	}

	override void reshape(ivec2 viewportSize)
	{
		glViewport(0, 0, viewportSize.x, viewportSize.y);
	}

	override void releaseWindow()
	{
		glfwDestroyWindow(glfwWindowPtr);
		glfwTerminate();
	}

	override void mousePosition(ivec2 newPosition) @property
	{
		glfwSetCursorPos(glfwWindowPtr, newPosition.x, newPosition.y);
	}

	override ivec2 mousePosition() @property
	{
		double x, y;
		glfwGetCursorPos(glfwWindowPtr, &x, &y);
		return ivec2(x, y) * pixelSize;
	}

	override void setVsync(bool value)
	{
		glfwSwapInterval(value);
	}

	override void swapBuffers()
	{
		glfwSwapBuffers(glfwWindowPtr);
	}

	override void size(ivec2 newSize) @property
	{
		glfwSetWindowSize(glfwWindowPtr, newSize.x, newSize.y);
	}

	override ivec2 size() @property
	{
		int width, height;
		glfwGetWindowSize(glfwWindowPtr, &width, &height);
		return ivec2(width, height);
	}

	override ivec2 framebufferSize() @property
	{
		int width, height;
		glfwGetFramebufferSize(glfwWindowPtr, &width, &height);
		return ivec2(width, height);
	}

	ivec2 pixelSize()
	{
		return framebufferSize / size;
	}

	override string clipboardString() @property
	{
		const(char*) data = glfwGetClipboardString(glfwWindowPtr);
		if (data is null) return "";
		return cast(string)fromStringz(data);
	}

	override void clipboardString(string newClipboardString) @property
	{
		glfwSetClipboardString(glfwWindowPtr, toStringz(newClipboardString));
	}

	override bool isKeyPressed(uint key)
	{
		return glfwGetKey(glfwWindowPtr, key) == GLFW_PRESS;
	}

	override void isCursorLocked(bool locked)
	{
		glfwSetInputMode(glfwWindowPtr, GLFW_CURSOR, locked ? GLFW_CURSOR_DISABLED : GLFW_CURSOR_NORMAL);
	}

	override bool isCursorLocked()
	{
		return glfwGetInputMode(glfwWindowPtr, GLFW_CURSOR) == GLFW_CURSOR_DISABLED;
	}

	override void setCursorIcon(CursorIcon icon)
	{
		glfwSetCursor(glfwWindowPtr, cursors[icon]);
	}

	GLFWwindow* handle() @property
	{
		return glfwWindowPtr;
	}

private:
	static void initGlfw()
	{
		glfwSetErrorCallback(&errorfun);

		if (glfwInit() == 0)
		{
			throw new Error("Error initializing GLFW3"); //TODO: add proper error handling
		}
		glfwInited = true;
	}
}

GlfwWindow getWinFromUP(GLFWwindow* w) nothrow
{
	GlfwWindow win;
	win = cast(GlfwWindow) glfwGetWindowUserPointer(w);
	return win;
}

extern(C) nothrow
{
	void errorfun(int errorCode, const(char)* msg)
	{
		throw new Error(format("GLFW error [%s] : %s", errorCode, fromStringz(msg)));
	}
	void windowposfun(GLFWwindow* w, int nx, int ny)
	{
		try getWinFromUP(w).windowMoved.emit(ivec2(nx, ny));
		catch(Exception e) throw new Error(to!string(e));
	}
	void windowsizefun(GLFWwindow* w, int newWidth, int newHeight)
	{
		try getWinFromUP(w).windowResized.emit(ivec2(newWidth, newHeight));
		catch(Exception e) throw new Error(to!string(e));
	}
	void windowclosefun(GLFWwindow* w)
	{
		try getWinFromUP(w).closePressed.emit();
		catch(Exception e) throw new Error(to!string(e));
	}
	void windowrefreshfun(GLFWwindow* w)
	{

	}
	void windowfocusfun(GLFWwindow* w, int focus)
	{
		try getWinFromUP(w).focusChanged.emit(cast(bool)focus);
		catch(Exception e) throw new Error(to!string(e));
	}
	void windowiconifyfun(GLFWwindow* w, int iconified)
	{
		try getWinFromUP(w).windowIconified.emit(cast(bool)iconified);
		catch(Exception e) throw new Error(to!string(e));
	}
	void mousebuttonfun(GLFWwindow* w, int mouseButton, int action, int mods)
	{
		try
		{
			if(action == GLFW_RELEASE)
			{
				getWinFromUP(w).mouseReleased.emit(cast(PointerButton)mouseButton, mods);
			}
			else
			{
				getWinFromUP(w).mousePressed.emit(cast(PointerButton)mouseButton, mods);
			}
		}
		catch(Exception e) throw new Error(to!string(e));
	}
	void cursorposfun(GLFWwindow* w, double nx, double ny)
	{
		try getWinFromUP(w).mouseMoved.emit(ivec2(cast(int)nx, cast(int)ny));
		catch(Exception e) throw new Error(to!string(e));
	}
	void scrollfun(GLFWwindow* w, double x, double y)
	{
		try getWinFromUP(w).wheelScrolled.emit(dvec2(x, y));
		catch(Exception e) throw new Error(to!string(e));
	}
	void cursorenterfun(GLFWwindow* w, int)
	{

	}
	void keyfun(GLFWwindow* w, int key, int, int action, int mods)
	{
		if (key < 0) return;
		try
		{
			if (action == GLFW_RELEASE)
			{
				getWinFromUP(w).keyReleased.emit(cast(KeyCode)key, mods);
			}
			else
			{
				getWinFromUP(w).keyPressed.emit(cast(KeyCode)key, mods);
			}
		}
		catch(Exception e) throw new Error(to!string(e));
	}
	void charfun(GLFWwindow* w, uint unicode)
	{
	    if (unicode > 0 && unicode < 0x10000) {
			try getWinFromUP(w).charEntered.emit(cast(dchar)unicode);
			catch(Exception e) throw new Error(to!string(e));
		}
	}
	void refreshfun(GLFWwindow* w)
	{
		try getWinFromUP(w).refresh.emit();
		catch(Exception e) throw new Error(to!string(e));
	}
}
