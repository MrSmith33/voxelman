/**
Copyright: Copyright (c) 2013-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.graphics.oglrenderer;

import derelict.opengl3.gl3;

import voxelman.math;
import voxelman.graphics.irenderer;
import voxelman.platform.iwindow;
import voxelman.graphics.shaderprogram;
import voxelman.graphics.texture;
import voxelman.graphics.glerrors;


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

	override void alphaBlending(bool value)
	{
		if (value) {
			checkgl!glEnable(GL_BLEND);
			checkgl!glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
		}
		else
			checkgl!glDisable(GL_BLEND);
	}

	override void depthWrite(bool value) {
		checkgl!glDepthMask(value);
	}

	override void depthTest(bool value) {
		if (value)
			checkgl!glEnable(GL_DEPTH_TEST);
		else
			checkgl!glDisable(GL_DEPTH_TEST);
	}

	override void faceCulling(bool value) {
		if (value)
			checkgl!glEnable(GL_CULL_FACE);
		else
			checkgl!glDisable(GL_CULL_FACE);
	}

	override void faceCullMode(FaceCullMode mode) {
		checkgl!glCullFace(mode);
	}

	override void wireFrameMode(bool value) {
		if (value)
			checkgl!glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
		else
			checkgl!glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
	}

	override void setViewport(ivec2 pos, ivec2 size) {
		checkgl!glViewport(pos.x, pos.y, size.x, size.y);
	}

	override void setClearColor(ubyte r, ubyte g, ubyte b, ubyte a = 255)
	{
		checkgl!glClearColor(cast(float)r/255, cast(float)g/255, cast(float)b/255, cast(float)a/255);
	}

	override SuperImage loadImage(string filename)
	{
		import dlib.image.io.io : dlib_loadImage = loadImage;
		import dlib.image.image : ImageRGBA8, convert, PixelFormat;
		SuperImage image = dlib_loadImage(filename);
		if (image.pixelFormat != PixelFormat.RGBA8)
			image = convert!ImageRGBA8(image);
		return image;
	}

	override Texture createTexture(SuperImage image)
	{
		return new Texture(image, TextureTarget.target2d, TextureFormat.rgba);
	}

	override ShaderProgram createShaderProgram(string vertexSource, string fragmentSource)
	{
		ShaderProgram newProgram = new ShaderProgram(vertexSource, fragmentSource);
		if (!newProgram.compile) throw new Exception(newProgram.errorLog);
		shaders ~= newProgram;
		return newProgram;
	}

	override ivec2 framebufferSize() @property
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
