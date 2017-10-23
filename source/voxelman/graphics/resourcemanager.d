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
	Bitmap bitmap;
	TextureAtlas texAtlas;
	Texture atlasTexture;
	FontManager fontManager;
	IRenderer renderer;
	string resourcePath;

	// used for solid coloring
	// allows rendering filled polygons together with textured polygons
	ivec2 whitePixelPos;

	this(string resourcePath, IRenderer renderer)
	{
		this.resourcePath = resourcePath;
		this.renderer = renderer;

		texAtlas = new TextureAtlas(256);
		bitmap = texAtlas.bitmap;
		atlasTexture = renderer.createTexture(bitmap);
		fontManager = new FontManager(buildPath(resourcePath, fontPath), texAtlas);
		findOrAddWhitePixel();
	}

	void reuploadTexture()
	{
		atlasTexture.loadFromImage(bitmap);
	}

	SpriteRef[string] loadNamedSpriteSheet(string name, TextureAtlas texAtlas, ivec2 spriteSize)
	{
		return .loadNamedSpriteSheet(buildPath(resourcePath, name), texAtlas, spriteSize);
	}

	SpriteSheetAnimationRef loadAnimation(string name)
	{
		return .loadSpriteSheetAnimation(name, texAtlas);
	}

	SpriteRef loadSprite(string name)
	{
		return .loadSprite(name, texAtlas);
	}

	void findOrAddWhitePixel()
	{
		import dlib.image.color : Color4f;
		foreach (col, x, y; bitmap)
		{
			if (col == Color4f(1, 1, 1))
			{
				whitePixelPos = ivec2(x, y);
				return;
			}
		}

		whitePixelPos = texAtlas.insert(ivec2(1, 1));
		bitmap[whitePixelPos.x, whitePixelPos.y] = Color4f(1, 1, 1);
	}
}
