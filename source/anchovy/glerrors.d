/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module anchovy.glerrors;

import std.conv: to;
import derelict.opengl3.gl3;

/// Errors checking template; should work in debug build.
/// Using: checkgl!glFunction(funcParams);
template checkgl(alias func)
{
    debug auto checkgl(string file = __FILE__, int line = __LINE__, Args...)(auto ref Args args)
    {
        scope(success) checkGlError(file, line, func.stringof);
        return func(args);
    } else
        alias checkgl = func;
}

void checkGlError(string file = __FILE__, size_t line = __LINE__, string funcName = "")
{
	uint error = glGetError();
	if (error != GL_NO_ERROR)
	{
		throw new OpenglException(error, file, line, funcName);
	}
}

class OpenglException : Exception
{
	this(uint errorCode, string file = __FILE__, size_t line = __LINE__, string funcName = "")
	{
		super("OpenGL error [" ~ to!string(errorCode) ~ "] " ~ glErrorStringTable[errorCode] ~ " " ~ funcName, file, line);
	}
}

static const string[uint] glErrorStringTable;

static this()
{
	glErrorStringTable =
		[
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
