/**
Copyright: Copyright (c) 2017-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.graphics.gl;

public import derelict.opengl;
import voxelman.log;
import std.conv: to;
import std.string : format;
import std.typecons : tuple;

mixin glFreeFuncs!(GLVersion.gl31);

void loadOpenGL()
{
	DerelictGL3.load();
}

void reloadOpenGL()
{
	import std.string : fromStringz;

	// Load maximum avaliable OpenGL version
	auto loaded = DerelictGL3.reload(); // calls loadExtensions below

	infof("OpenGL %s", glGetString(GL_VERSION).fromStringz);
	infof("Vendor %s", glGetString(GL_VENDOR).fromStringz);
	infof("Renderer %s", glGetString(GL_RENDERER).fromStringz);

}


//enum EXTERNAL_VIRTUAL_MEMORY_BUFFER_AMD = 0x9160;
//__gshared bool AMD_pinned_memory;

// GL_ARB_debug_output
//import derelict.opengl.extensions.arb_d;
//mixin(arbDebugOutput);
//__gshared bool GL_ARB_debug_output_supported;

// GL_KHR_debug
import derelict.opengl.extensions.khr;
mixin(khrDebug);
__gshared bool GL_KHR_debug_supported;


// Is called by DerelictGL3.reload, because of mixin glFreeFuncs
// `static if(is(typeof(loadExtensions()))) loadExtensions();` in derelict.opengl.impl
void loadExtensions()
{
	//AMD_pinned_memory = DerelictGL3.isExtensionSupported("GL_AMD_pinned_memory");
	//GL_ARB_debug_output_supported = DerelictGL3.isExtensionSupported("GL_ARB_debug_output");
	//infof("GL_ARB_debug_output %s", GL_ARB_debug_output_supported);
	GL_KHR_debug_supported = DerelictGL3.isExtensionSupported("GL_KHR_debug");
	infof("GL_KHR_debug %s", GL_KHR_debug_supported);
}

void setupGLDebugLogging()
{
	int flags;
	glGetIntegerv(GL_CONTEXT_FLAGS, &flags);
	if (flags & GL_CONTEXT_FLAG_DEBUG_BIT)
	{
		// initialize debug output
		infof("Debug context inited");
		glEnable(GL_DEBUG_OUTPUT);
		glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS);
		glDebugMessageCallback(&glDebugLog, null);
		glDebugMessageControl(GL_DONT_CARE, GL_DONT_CARE, GL_DONT_CARE, 0, null, GL_TRUE);

		// test
		glDebugMessageInsert(GL_DEBUG_SOURCE_APPLICATION, GL_DEBUG_TYPE_ERROR, 0,
			GL_DEBUG_SEVERITY_MEDIUM, -1, "Testing error callback");
	}
	else
	{
		infof("Debug context not inited");
	}
}

extern(System) void glDebugLog(
	GLenum source,
	GLenum type,
	GLuint id,
	GLenum severity,
	GLsizei length,
	const GLchar* message,
	const void* userParam) nothrow
{
	string sourceStr;
	switch (source)
	{
		case GL_DEBUG_SOURCE_API:             sourceStr = "API"; break;
		case GL_DEBUG_SOURCE_WINDOW_SYSTEM:   sourceStr = "Window System"; break;
		case GL_DEBUG_SOURCE_SHADER_COMPILER: sourceStr = "Shader Compiler"; break;
		case GL_DEBUG_SOURCE_THIRD_PARTY:     sourceStr = "Third Party"; break;
		case GL_DEBUG_SOURCE_APPLICATION:     sourceStr = "Application"; break;
		case GL_DEBUG_SOURCE_OTHER:           sourceStr = "Other"; break;
		default: break;
	}

	string typeStr;
	switch (type)
	{
		case GL_DEBUG_TYPE_ERROR:               typeStr = "Error"; break;
		case GL_DEBUG_TYPE_DEPRECATED_BEHAVIOR: typeStr = "Deprecated Behaviour"; break;
		case GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR:  typeStr = "Undefined Behaviour"; break;
		case GL_DEBUG_TYPE_PORTABILITY:         typeStr = "Portability"; break;
		case GL_DEBUG_TYPE_PERFORMANCE:         typeStr = "Performance"; break;
		case GL_DEBUG_TYPE_MARKER:              typeStr = "Marker"; break;
		case GL_DEBUG_TYPE_PUSH_GROUP:          typeStr = "Push Group"; break;
		case GL_DEBUG_TYPE_POP_GROUP:           typeStr = "Pop Group"; break;
		case GL_DEBUG_TYPE_OTHER:               typeStr = "Other"; break;
		default: break;
	}

	string severityStr;
	switch (severity)
	{
		case GL_DEBUG_SEVERITY_HIGH:         severityStr = "high"; break;
		case GL_DEBUG_SEVERITY_MEDIUM:       severityStr = "medium"; break;
		case GL_DEBUG_SEVERITY_LOW:          severityStr = "low"; break;
		case GL_DEBUG_SEVERITY_NOTIFICATION: severityStr = "notification"; break;
		default: break;
	}

	try {
		infof("[GL] source: %s, type: %s, id: %s, severity: %s, msg: \"%s\"",
			sourceStr, typeStr, id, severityStr, message[0..length]);
	}
	catch(Exception){}
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

int openglMajorVersion(GLVersion openglVersion) {
	final switch(openglVersion) with (GLVersion) {
		case gl11, gl12, gl13, gl14, gl15: return 1;
		case gl20, gl21: return 2;
		case gl30, gl31, gl32, gl33: return 3;
		case gl40, gl41, gl42, gl43, gl44, gl45: return 4;
		case none: return 0;
	}
}

int openglMinorVersion(GLVersion openglVersion) {
	final switch(openglVersion) with (GLVersion) {
		case gl20, gl30, gl40: return 0;
		case gl11, gl21, gl31, gl41: return 1;
		case gl12, gl32, gl42: return 2;
		case gl13, gl33, gl43: return 3;
		case gl14, gl44: return 4;
		case gl15, gl45: return 5;
		case none: return 0;
	}
}

GLVersion toGLVersion(int major, int minor)
{
	switch(major) {
		case 4:
			if(minor == 5) return GLVersion.gl45;
			else if(minor == 4) return GLVersion.gl44;
			else if(minor == 3) return GLVersion.gl43;
			else if(minor == 2) return GLVersion.gl42;
			else if(minor == 1) return GLVersion.gl41;
			else if(minor == 0) return GLVersion.gl40;

			/* No default condition here, since its possible for new
			 minor versions of the 4.x series to be released before
			 support is added to Derelict. That case is handled outside
			 of the switch. When no more 4.x versions are released, this
			 should be changed to return GL40 by default. */
			break;

		case 3:
			if(minor == 3) return GLVersion.gl33;
			else if(minor == 2) return GLVersion.gl32;
			else if(minor == 1) return GLVersion.gl31;
			else return GLVersion.gl30;

		case 2:
			if(minor == 1) return GLVersion.gl21;
			else return GLVersion.gl20;

		case 1:
			if(minor == 5) return GLVersion.gl15;
			else if(minor == 4) return GLVersion.gl14;
			else if(minor == 3) return GLVersion.gl13;
			else if(minor == 2) return GLVersion.gl12;
			else return GLVersion.gl11;

		default:
			/* glGetString(GL_VERSION) is guaranteed to return a result
			 of a specific format, so if this point is reached it is
			 going to be because a major version higher than what Derelict
			 supports was encountered. That case is handled outside the
			 switch. */
			break;
	}

	/* It's highly likely at this point that the version is higher than
	 what Derelict supports, so return the highest supported version. */
	return GLVersion.highestSupported;
}
