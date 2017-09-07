/**
Copyright: Copyright (c) 2013-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.graphics.texture;

import std.conv, std.file;
import std.stdio;
import std.string;

import voxelman.graphics.gl;
import dlib.image.image : SuperImage;

//version = debugTexture;

enum TextureTarget : uint
{
	target1d = GL_TEXTURE_1D,
	target2d = GL_TEXTURE_2D,
	target3d = GL_TEXTURE_3D,
	targetRectangle = GL_TEXTURE_RECTANGLE,
	targetBuffer = GL_TEXTURE_BUFFER,
	targetCubeMap = GL_TEXTURE_CUBE_MAP,
	target1dArray = GL_TEXTURE_1D_ARRAY,
	target2dArray = GL_TEXTURE_2D_ARRAY,
	targetCubeMapArray = GL_TEXTURE_CUBE_MAP_ARRAY,
	target2dMultisample = GL_TEXTURE_2D_MULTISAMPLE,
	target2dMultisampleArray = GL_TEXTURE_2D_MULTISAMPLE_ARRAY,
}

enum TextureFormat : uint
{
	r = GL_RED,
	rg = GL_RG,
	rgb = GL_RGB,
	rgba = GL_RGBA,
}

class Texture
{
private:
	TextureFormat texFormat;
	uint glTextureHandle;
	TextureTarget texTarget;

public:
	this(SuperImage image, TextureTarget target, TextureFormat format)
	{
		texTarget = target;
		texFormat = format;
		checkgl!glGenTextures(1, &glTextureHandle);
		loadFromImage(image);
	}

	void bind(uint textureUnit = 0)
	{
		checkgl!glActiveTexture(GL_TEXTURE0 + textureUnit);
		checkgl!glBindTexture(texTarget, glTextureHandle);
	}

	void unbind()
	{
		checkgl!glBindTexture(texTarget, 0);
	}

	static void unbind(TextureTarget target)
	{
		checkgl!glBindTexture(target, 0);
	}

	void loadFromImage(SuperImage img)
	{
		bind();
		checkgl!glTexImage2D(texTarget, 0, texFormat, img.width, img.height, 0, texFormat, GL_UNSIGNED_BYTE, img.data.ptr);
		checkgl!glTexParameteri(texTarget, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		checkgl!glTexParameteri(texTarget, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		unbind();
	}

	void unload()
	{
		glDeleteTextures(1, &glTextureHandle);
	}
}
