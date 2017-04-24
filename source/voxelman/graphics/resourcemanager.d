/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.graphics.resourcemanager;

import voxelman.graphics;

final class ResourceManager
{
	Bitmap bitmap;
	TextureAtlas texAtlas;
	Texture atlasTexture;
	FontManager fontManager;
	IRenderer renderer;

	this(IRenderer renderer)
	{
		this.renderer = renderer;
		texAtlas = new TextureAtlas(256);
		bitmap = texAtlas.bitmap;
		atlasTexture = renderer.createTexture(bitmap);
		fontManager = new FontManager(texAtlas);
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
}
