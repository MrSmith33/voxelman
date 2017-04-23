/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.graphics.font.bitmapfontloader;

import voxelman.math;
import dlib.image.io.png;
import voxelman.graphics.bitmap;
import voxelman.graphics.font.font;
import voxelman.graphics.textureatlas;

import std.stdio;

void loadBitmapFont(Font* font, TextureAtlas texAtlas, in dchar[] chars)
{
	auto image = new Bitmap(loadPNG(font.filename));
	if (image.width == 0 || image.height == 0) return;

	font.metrics.monoAdvanceX = 7;
	font.metrics.lineGap = 12;

	auto sentinelPixel = image[0,0];
	//writefln("sent %s", sentinelPixel);

	ivec2 cursor;

	int nextCursorX;
	void checkNextChar()
	{
		nextCursorX = cursor.x+1;
		while (nextCursorX < image.width && image[nextCursorX, cursor.y] != sentinelPixel)
		{
			++nextCursorX;
		}
	}

	int nextLineY;
	void checkNextLine()
	{
		if (cursor.x == 0) // new line
		{
			nextLineY = cursor.y+1;
			while (nextLineY < image.height && image[0, nextLineY] != sentinelPixel)
			{
				++nextLineY;
			}
		}
	}

	void advanceCursor()
	{
		if (cursor.x >= image.width)
		{
			cursor.x = 0;
			cursor.y = nextLineY;
		}
		else
		{
			cursor.x = nextCursorX;
		}
	}

	bool isValidCursor()
	{
		return cursor.x < image.width && cursor.y < image.height;
	}

	foreach (dchar glyph; chars)
	{
		//writefln("glyph '%s'", glyph);
		checkNextChar();
		checkNextLine();

		if (!isValidCursor()) break;

		// load glyph
		auto glyphStart = cursor + ivec2(1,0);

		int glyphWidth = nextCursorX - cursor.x - 1;
		int glyphHeight = nextLineY - cursor.y - 1;
		auto glyphSize = ivec2(glyphWidth, glyphHeight);

		// write to texture
		ivec2 atlasPos = texAtlas.insert(image, irect(glyphStart, glyphSize));

		int glyphOffsetX = 0;
		int glyphOffsetY = 0;

		int glyphAdvanceX = glyphWidth + 1;
		int glyphAdvanceY = glyphHeight + 1;

		auto metrics = GlyphMetrics(
			glyphWidth, glyphHeight,
			glyphOffsetX, glyphOffsetY,
			glyphAdvanceX, glyphAdvanceY);

		//writefln("glyph '%s' %s %s", glyph, atlasPos, metrics);

		font.glyphs[glyph] = Glyph(atlasPos, metrics);

		advanceCursor();
	}
}
