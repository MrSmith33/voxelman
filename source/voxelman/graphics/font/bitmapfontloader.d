/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.graphics.font.bitmapfontloader;

import dlib.image.io.png;
import voxelman.math;
import voxelman.graphics.image.crop;
import voxelman.graphics.bitmap;
import voxelman.graphics.font.font;
import voxelman.graphics.textureatlas;

import std.stdio;

void loadBitmapFont(Font* font, TextureAtlas texAtlas, in dchar[] chars)
{
	auto image = new Bitmap(loadPNG(font.filename));
	if (image.width == 0 || image.height == 0) return;

	auto sentinelPixel = image[0,0];
	//writefln("sent %s", sentinelPixel);

	ivec2 cursor;

	int nextCursorX;
	// find a pixel past the end of current char
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
		if (nextCursorX >= image.width)
		{
			cursor.x = 0;
			cursor.y = nextLineY;
		}
		else
		{
			cursor.x = nextCursorX;

			// check if end of line
			// either sentinel + end or two sentinels
			int rightPixel = cursor.x + 1;
			if (rightPixel == image.width || image[rightPixel, cursor.y] == sentinelPixel)
			{
				// newline
				cursor.x = 0;
				cursor.y = nextLineY;
			}
		}
	}

	bool isValidCursor()
	{
		return cursor.x < image.width && cursor.y < image.height;
	}

	int maxGlyphWidth = 0;
	int maxGlyphHeight = 0;

	void loadGlyph(dchar glyph)
	{
		// load glyph
		auto glyphStart = cursor + ivec2(1,0);
		auto glyphStartCopy = glyphStart;

		int glyphWidth = nextCursorX - cursor.x - 1;
		int glyphHeight = nextLineY - cursor.y;
		auto glyphSize = ivec2(glyphWidth, glyphHeight);

		// crop all transparent pixels
		cropImage(image, glyphStart, glyphSize);

		// write to texture
		ivec2 atlasPos = texAtlas.insert(image, irect(glyphStart, glyphSize));

		ivec2 glyphOffset = glyphStart - glyphStartCopy;

		int glyphAdvanceX = glyphSize.x + 1;
		int glyphAdvanceY = glyphSize.y + 1;

		auto metrics = GlyphMetrics(
			glyphSize.x, glyphSize.y,
			glyphOffset.x, -glyphOffset.y,
			glyphAdvanceX, glyphAdvanceY);

		maxGlyphWidth = max(maxGlyphWidth, glyphSize.x);
		// use uncropped height here since there can be no glyphs
		// that reach both top and bottom of line
		maxGlyphHeight = max(maxGlyphHeight, glyphHeight);

		//writefln("glyph '%s' img pos %s size %s", glyph, glyphStart, glyphSize);

		font.glyphs[glyph] = Glyph(atlasPos, metrics);
	}

	foreach (dchar glyph; chars)
	{
		checkNextChar();
		checkNextLine();

		if (!isValidCursor()) break;

		loadGlyph(glyph);

		advanceCursor();
	}

	font.metrics.width = maxGlyphWidth;
	font.metrics.height = maxGlyphHeight;
	font.metrics.advanceX = maxGlyphWidth + 1;
	font.metrics.advanceY = maxGlyphHeight + 1;
	//writefln("font %s", font.metrics);
}
