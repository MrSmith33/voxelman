/**
Copyright: Copyright (c) 2013-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.graphics.shaderprogram;

import std.exception;
import std.stdio;
import std.string;
import std.variant;
import voxelman.graphics.gl;

final class ShaderProgram
{
	bool isInited;
	GLuint handle = 0;
	string errorLog;

	this(in string vertShaderSource, in string fragShaderSource)
	{
		handle = checkgl!glCreateProgram();
		attachShader(GL_VERTEX_SHADER, vertShaderSource);
		attachShader(GL_FRAGMENT_SHADER, fragShaderSource);
		isInited = true;
	}

	void close()
	{
		if (isInited) {
			checkgl!glDeleteProgram(handle);
			isInited = false;
		}
	}

	void bind()
	{
		checkgl!glUseProgram(handle);
	}

	static void unbind()
	{
		checkgl!glUseProgram(0);
	}

	void attachShader(in GLenum shaderType, in string shaderSource)
	{
		GLuint shader = checkgl!glCreateShader(shaderType);

		const char* fileData = toStringz(shaderSource);
		checkgl!glShaderSource(shader, 1, &fileData, null);
		checkgl!glCompileShader(shader);

		int status;
		checkgl!glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
		if (status == GL_FALSE)
		{
			int length;
			glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &length);

			char[] error = new char[length];
			checkgl!glGetShaderInfoLog(shader, length, null, cast(char*)error);

			string shaderTypeString;
			switch(shaderType)
			{
				case GL_VERTEX_SHADER:   shaderTypeString = "vertex"; break;
				//case GL_GEOMETRY_SHADER: shaderTypeString = "geometry"; break; // not supported in OpenGL 3.1
				case GL_FRAGMENT_SHADER: shaderTypeString = "fragment"; break;
				default: break;
			}

			errorLog ~= "Compile failure in " ~ shaderTypeString ~ " shader:\n" ~ error~"\n";
		}
		checkgl!glAttachShader(handle, shader);
	}

	// if ( !myShaderProgram.compile() )
	//     writeln( myShaderProgram.errorLog );
	bool compile()
	{
		checkgl!glLinkProgram(handle);

		GLint linkStatus;
		checkgl!glGetProgramiv(handle, GL_LINK_STATUS, &linkStatus);

		scope(exit) // Detach all shaders after compilation
		{
			GLuint[3] shaders;
			GLsizei count;

			checkgl!glGetAttachedShaders(handle, cast(int)shaders.length, &count, cast(uint*)shaders);

			for( uint i=0; i<count; ++i )
			{
				checkgl!glDetachShader(handle, shaders[i]);
				checkgl!glDeleteShader(shaders[i]);
			}
		}

		if ( linkStatus == GL_FALSE )
		{
			GLint infoLogLength;
			checkgl!glGetProgramiv(handle, GL_INFO_LOG_LENGTH, &infoLogLength);

			char[] strInfoLog = new char[infoLogLength];
			checkgl!glGetProgramInfoLog(handle, infoLogLength, null, cast(char*)strInfoLog);
			errorLog ~= "Linker failure: " ~ strInfoLog ~ "\n";

			return false;
		}
		return true;
	}
}
