/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.graphics.gl;

public import derelict.opengl;
import std.conv: to;
import std.string : format;
import std.typecons : tuple;

void loadOpenGL()
{
	DerelictGL3.load();
}

void reloadOpenGL()
{
	// Load maximum avaliable OpenGL version
	DerelictGL3.reload();
	loadExtensions();
}


enum EXTERNAL_VIRTUAL_MEMORY_BUFFER_AMD = 0x9160;
__gshared bool AMD_pinned_memory;

void loadExtensions()
{
	AMD_pinned_memory = DerelictGL3.isExtensionSupported("GL_AMD_pinned_memory");
}


/// Error checking template; should work in debug build.
/// Usage: checkgl!glFunction(funcParams);
template checkgl(alias func)
{
	import std.traits : Parameters;
	debug auto checkgl(string file = __FILE__, int line = __LINE__)(Parameters!func args)
	{
		scope(success) checkGlError(file, line, func.stringof, args);
		return func(args);
	} else
		alias checkgl = func;
}

void checkGlError(string file = __FILE__, size_t line = __LINE__)
{
	uint error = glGetError();
	if (error != GL_NO_ERROR)
	{
		auto msg = format("OpenGL error \"%s\" [%s]", glErrorStringTable[error], error);
		throw new OpenglException(msg, file, line);
	}
}

void checkGlError(Args...)(string file, size_t line, string funcName, Args args)
{
	uint error = glGetError();
	if (error != GL_NO_ERROR)
	{
		auto msg = format("%s(%(%s%|, %)): \"%s\" [%s]", funcName, tuple(args), glErrorStringTable[error], error);
		throw new OpenglException(msg, file, line);
	}
}

class OpenglException : Exception
{
	this(string msg, string file = __FILE__, size_t line = __LINE__)
	{
		super(msg, file, line);
	}
}

static const string[uint] glErrorStringTable;

static this()
{
	glErrorStringTable = [
		//GL_NO_ERROR : "no error",
		GL_INVALID_ENUM : "invalid enum",
		GL_INVALID_VALUE : "invalid value",
		GL_INVALID_OPERATION : "invalid operation",
		GL_INVALID_FRAMEBUFFER_OPERATION : "invalid framebuffer operation",
		GL_OUT_OF_MEMORY : "out of memory",
		//GL_STACK_UNDERFLOW : "stack underflow",
		//GL_STACK_OVERFLOW : "stack overflow",
		];
}
