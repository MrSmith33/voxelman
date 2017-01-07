/**
Copyright: Copyright (c) 2013-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module anchovy.oglrenderer;

import derelict.opengl3.gl3;


import voxelman.math;
import anchovy.irenderer;
import anchovy.iwindow;
import anchovy.shaderprogram;
import anchovy.texture;

class Vao
{
	this()
	{
		glGenVertexArrays(1, &handle);
	}
	void close()
	{
		glDeleteVertexArrays(1, &handle);
	}
	void bind()
	{
		glBindVertexArray(handle);
	}

	static void unbind()
	{
		glBindVertexArray(0);
	}
	uint handle;
}

class OglRenderer : IRenderer
{
private:
	ShaderProgram[] shaders;

	IWindow	window;

public:
	this(IWindow window)
	{
		this.window = window;
	}

	override void enableAlphaBlending()
	{
		glEnable(GL_BLEND);
		glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	}

	override void disableAlphaBlending()
	{
		glDisable(GL_BLEND);
	}

	override void setClearColor(ubyte r, ubyte g, ubyte b, ubyte a = 255)
	{
		glClearColor(cast(float)r/255, cast(float)g/255, cast(float)b/255, cast(float)a/255);
	}

	override Texture createTexture(string filename)
	{
		import dlib.image.io.io : loadImage;
		import dlib.image.image : SuperImage, ImageRGBA8, convert;
		SuperImage image = loadImage(filename);
		SuperImage convertedImage = convert!ImageRGBA8(image);
		Texture tex = new Texture(convertedImage, TextureTarget.target2d, TextureFormat.rgba);
		return tex;
	}

	override ShaderProgram createShaderProgram(string vertexSource, string fragmentSource)
	{
		ShaderProgram newProgram = new ShaderProgram(vertexSource, fragmentSource);
		if (!newProgram.compile) throw new Exception(newProgram.errorLog);
		shaders ~= newProgram;
		return newProgram;
	}

	override uvec2 framebufferSize() @property
	{
		return window.framebufferSize();
	}

	override void flush()
	{
		window.swapBuffers;
	}

	override void close()
	{
		foreach(shader; shaders)
		{
			shader.close;
		}
		shaders = null;
	}
}
