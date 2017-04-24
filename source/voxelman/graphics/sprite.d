/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.graphics.sprite;

import voxelman.math;
import voxelman.graphics;

SpriteRef loadSprite(string filename, TextureAtlas texAtlas)
{
	import dlib.image.io.png;
	import std.path : setExtension;
	string imageFilename = setExtension(filename, "png");
	auto image = new Bitmap(loadPNG(imageFilename));
	irect atlasRect = putSpriteIntoAtlas(image, irect(0,0,image.width, image.height), texAtlas);
	return new Sprite(atlasRect);
}

irect putSpriteIntoAtlas(Bitmap sourceBitmap, irect spriteRect, TextureAtlas texAtlas)
{
	ivec2 position = texAtlas.insert(sourceBitmap, spriteRect);
	return irect(position, spriteRect.size);
}

struct Sprite
{
	irect atlasRect;
}

alias SpriteRef = Sprite*;

struct SpriteInstance
{
	SpriteRef sprite;

	vec2 scale = vec2(1, 1);
	vec2 origin = vec2(0, 0);
}
