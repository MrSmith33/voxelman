/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.graphics.sprite;

import dlib.image.io.png;
import std.path : setExtension;
import std.stdio;
import std.range : zip;
import voxelman.math;
import voxelman.graphics;
import voxelman.graphics.image.crop;

SpriteRef loadSprite(string filename, TextureAtlas texAtlas)
{
	string imageFilename = setExtension(filename, "png");
	auto image = new Bitmap(loadPNG(imageFilename));
	irect atlasRect = putSpriteIntoAtlas(image, irect(0,0,image.width, image.height), texAtlas);
	return new Sprite(atlasRect);
}

SpriteRef[string] loadNamedSpriteSheet(string filename, TextureAtlas texAtlas, ivec2 spriteSize)
{
	string descriptionFilename = setExtension(filename, "txt");
	auto file = File(descriptionFilename);

	SpriteRef[] spriteArray = loadIndexedSpriteSheet(filename, texAtlas, spriteSize);
	size_t spriteIndex;

	SpriteRef[string] spriteMap;
	foreach(nameValue; zip(file.byLineCopy(), spriteArray))
	{
		spriteMap[nameValue[0]] = nameValue[1];
	}

	return spriteMap;
}

SpriteRef[] loadIndexedSpriteSheet(string filename, TextureAtlas texAtlas, ivec2 spriteSize)
{
	string imageFilename = setExtension(filename, "png");
	auto image = new Bitmap(loadPNG(imageFilename));

	SpriteRef[] sprites;
	size_t spriteIndex;

	ivec2 imageSize = ivec2(image.width, image.height);
	ivec2 gridSize = imageSize / spriteSize;
	sprites.length = gridSize.x * gridSize.y;

	foreach(j; 0..gridSize.y)
	foreach(i; 0..gridSize.x)
	{
		irect spriteSubRect = irect(ivec2(i,j) * spriteSize, spriteSize);
		cropImage(image, spriteSubRect.position, spriteSubRect.size);

		irect atlasRect = putSpriteIntoAtlas(image, spriteSubRect, texAtlas);
		sprites[spriteIndex++] = new Sprite(atlasRect);
	}

	return sprites;
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
