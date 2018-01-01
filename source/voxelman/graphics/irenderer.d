/**
Copyright: Copyright (c) 2013-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.graphics.irenderer;

import voxelman.math;
import voxelman.graphics.texture;
import voxelman.graphics.shaderprogram;
public import dlib.image.image : SuperImage;

interface IRenderer
{
	void alphaBlending(bool value);
	void rectClipping(bool value);
	void depthWrite(bool value);
	void depthTest(bool value);
	void faceCulling(bool value);
	void faceCullMode(FaceCullMode mode);
	void wireFrameMode(bool value);
	void setViewport(ivec2 pos, ivec2 size);
	void setClipRect(irect rect);
	void setClearColor(ubyte r, ubyte g, ubyte b, ubyte a = 255);
	SuperImage loadImage(string filename);
	Texture createTexture(SuperImage image);
	ShaderProgram createShaderProgram(string vertexSource, string fragmentSource);
	ivec2 framebufferSize() @property;
	void flush();
	void close();
}

import voxelman.graphics.gl;
enum FaceCullMode
{
	front = GL_FRONT,
	back = GL_BACK,
	frontAndBack = GL_FRONT_AND_BACK
}
