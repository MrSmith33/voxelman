/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.graphics.resourcemanager;

import std.path : buildPath;
import voxelman.math;
import voxelman.graphics;

enum string fontPath = "font";

final class ResourceManager
{
	TextureAtlas texAtlas;
	FontManager fontManager;
	string resourcePath;

	// used for solid coloring
	// allows rendering filled polygons together with textured polygons
	ivec2 whitePixelPos;

	this(string resourcePath)
	{
		this.resourcePath = resourcePath;

		texAtlas = new TextureAtlas(256);
		fontManager = new FontManager(buildPath(resourcePath, fontPath), texAtlas);
		findOrAddWhitePixel();
	}

	SpriteRef[string] loadNamedSpriteSheet(string name, ivec2 spriteSize) {
		return .loadNamedSpriteSheet(buildPath(resourcePath, name), texAtlas, spriteSize);
	}
	SpriteRef[string] loadNamedSpriteSheet(string name, TextureAtlas texAtlas, ivec2 spriteSize) {
		return .loadNamedSpriteSheet(buildPath(resourcePath, name), texAtlas, spriteSize);
	}

	SpriteRef[] loadIndexedSpriteSheet(string name, ivec2 spriteSize) {
		return .loadIndexedSpriteSheet(buildPath(resourcePath, name), texAtlas, spriteSize);
	}
	SpriteRef[] loadIndexedSpriteSheet(string name, TextureAtlas texAtlas, ivec2 spriteSize) {
		return .loadIndexedSpriteSheet(buildPath(resourcePath, name), texAtlas, spriteSize);
	}

	SpriteSheetAnimationRef loadAnimation(string name)
	{
		return .loadSpriteSheetAnimation(buildPath(resourcePath, name), texAtlas);
	}

	SpriteRef loadSprite(string name)
	{
		return .loadSprite(buildPath(resourcePath, name), texAtlas);
	}

	void findOrAddWhitePixel()
	{
		import dlib.image.color : Color4f;
		foreach (col, x, y; texAtlas.bitmap)
		{
			if (col == Color4f(1, 1, 1))
			{
				whitePixelPos = ivec2(x, y);
				return;
			}
		}

		whitePixelPos = texAtlas.insert(ivec2(1, 1));
		texAtlas.bitmap[whitePixelPos.x, whitePixelPos.y] = Color4f(1, 1, 1);
	}
}
