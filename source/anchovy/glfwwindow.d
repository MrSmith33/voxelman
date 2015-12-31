/**
Copyright: Copyright (c) 2013-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module anchovy.glfwwindow;

import std.conv : to;
import std.string : toStringz, fromStringz, format;

import derelict.glfw3.glfw3;
import derelict.opengl3.gl3;
import dlib.math.vector;
import anchovy.iwindow : IWindow;

class GlfwWindow : IWindow
{
private:
	GLFWwindow*	_window;
	bool _mouseGrabbed = false;
	static bool	glfwInited = false;

public:
	override void init(uvec2 size, in string caption)
	{
		if (!glfwInited)
			initGlfw();

		scope(failure) glfwTerminate();

		//BUG: sometimes fails in Windows 8. Maybe because of old drivers.
		_window = glfwCreateWindow(size.x, size.y, toStringz(caption), null,  null);

		if (_window is null)
		{
			throw new Error("Error creating GLFW3 window");
		}

		glfwMakeContextCurrent(_window);
		glfwSwapInterval(0);

		glClearColor(1.0, 1.0, 1.0, 1.0);
		glViewport(0, 0, size.x, size.y);

		DerelictGL3.reload();

		glfwSetWindowUserPointer(_window, cast(void*)this);
		glfwSetWindowPosCallback(_window, &windowposfun);
		glfwSetFramebufferSizeCallback(_window, &windowsizefun);
		glfwSetWindowCloseCallback(_window, &windowclosefun);
		//glfwSetWindowRefreshCallback(_window, &windowrefreshfun);
		glfwSetWindowFocusCallback(_window, &windowfocusfun);
		glfwSetWindowIconifyCallback(_window, &windowiconifyfun);
		glfwSetMouseButtonCallback(_window, &mousebuttonfun);
		glfwSetCursorPosCallback(_window, &cursorposfun);
		glfwSetScrollCallback(_window, &scrollfun);
		glfwSetKeyCallback(_window, &keyfun);
		glfwSetCharCallback(_window, &charfun);
		//glfwSetCursorEnterCallback(window, GLFWcursorenterfun cbfun);
	}

	override void processEvents()
	{
		glfwPollEvents();
	}

	override double elapsedTime() @property //in seconds
	{
		return glfwGetTime();
	}

	override void reshape(uvec2 viewportSize)
	{
		glViewport(0, 0, cast(int)viewportSize.x, cast(int)viewportSize.y);
	}

	override void releaseWindow()
	{
		glfwDestroyWindow(_window);
		glfwTerminate();
	}

	override void mousePosition(ivec2 newPosition) @property
	{
		glfwSetCursorPos(_window, newPosition.x, newPosition.y);
	}

	override ivec2 mousePosition() @property
	{
		double x, y;
		glfwGetCursorPos(_window, &x, &y);
		return ivec2(cast(int)x, cast(int)y);
	}

	override void swapBuffers()
	{
		glfwSwapBuffers(_window);
	}

	override void size(uvec2 newSize) @property
	{
		glfwSetWindowSize(_window, cast(int)newSize.x, cast(int)newSize.y);
	}

	override uvec2 size() @property
	{
		int width, height;
		glfwGetWindowSize(_window, &width, &height);
		return uvec2(cast(uint)width, cast(uint)height);
	}

	override uvec2 framebufferSize() @property
	{
		int width, height;
		glfwGetFramebufferSize(_window, &width, &height);
		return uvec2(cast(uint)width, cast(uint)height);
	}

	override string clipboardString() @property
	{
		const(char*) data = glfwGetClipboardString(_window);
		if (data is null) return "";
		return cast(string)fromStringz(data);
	}

	override void clipboardString(string newClipboardString) @property
	{
		glfwSetClipboardString(_window, toStringz(newClipboardString));
	}

	override bool isKeyPressed(uint key)
	{
		return glfwGetKey(_window, key) == GLFW_PRESS;
	}

	GLFWwindow* handle() @property
	{
		return _window;
	}

private:
	static void initGlfw()
	{
		glfwSetErrorCallback(&errorfun);

		if (glfwInit() == 0)
		{
			throw new Error("Error initializing GLFW3"); //TODO: add proper error handling
		}

		glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
		glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);
		//glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

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
		try getWinFromUP(w).windowResized.emit(uvec2(cast(uint)newWidth, cast(uint)newHeight));
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
	void mousebuttonfun(GLFWwindow* w, int mouseButton, int action, int)
	{
		try
		{
			if(action == GLFW_RELEASE)
			{
				getWinFromUP(w).mouseReleased.emit(mouseButton);
			}
			else
			{
				getWinFromUP(w).mousePressed.emit(mouseButton);
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
	void keyfun(GLFWwindow* w, int key, int, int action, int)
	{
		try
		{
			if (action == GLFW_RELEASE)
			{
				getWinFromUP(w).keyReleased.emit(key);
			}
			else
			{
				getWinFromUP(w).keyPressed.emit(key);
			}
		}
		catch(Exception e) throw new Error(to!string(e));
	}
	void charfun(GLFWwindow* w, uint unicode)
	{
		try getWinFromUP(w).charEntered.emit(cast(dchar)unicode);
		catch(Exception e) throw new Error(to!string(e));
	}
}
