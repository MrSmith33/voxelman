/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.graphics.resourcemanager;

import voxelman.math;
import voxelman.graphics;

final class ResourceManager
{
	Bitmap bitmap;
	TextureAtlas texAtlas;
	Texture atlasTexture;
	FontManager fontManager;
	IRenderer renderer;

	// used for solid coloring
	// allows rendering filled polygons together with textured polygons
	ivec2 whitePixelPos;

	this(IRenderer renderer)
	{
		this.renderer = renderer;
		texAtlas = new TextureAtlas(256);
		bitmap = texAtlas.bitmap;
		atlasTexture = renderer.createTexture(bitmap);
		fontManager = new FontManager(texAtlas);
		findOrAddWhitePixel();
	}

	void reuploadTexture()
	{
		atlasTexture.loadFromImage(bitmap);
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
