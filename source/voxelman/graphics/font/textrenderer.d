/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.graphics.font.textrenderer;

import voxelman.math;
import voxelman.graphics;
import voxelman.graphics.font.font;

struct TextRendererAppender
{
	TextRenderer* renderer;
	Font* font;
	Color4ub color;
	int scale = 1;

	//void put(dchar chr)
	//{
	//	renderer.appendGlyphs(only(chr), font, color, scale);
	//}
	void put(Range)(Range chars)
	{
		renderer.appendGlyphs(chars, font, color, scale);
	}
}

struct TextRenderer
{
	TexturedBatch2d* sink;
	Texture texture;
	ivec2 origin;
	ivec2 cursor;

	uint tabSize = 4;

	void appendGlyphs(R)(R textRange, Font* font, Color4ub color, int scale = 1)
	{
		foreach(dchar chr; textRange)
		{
			Glyph* glyph = font.getGlyph(chr);

			if (glyph is null) glyph = font.getGlyph('?');

			if (chr == ' ')
			{
				cursor.x += glyph.metrics.advanceX * scale;
				continue;
			}
			else if (chr == '\t')
			{
				cursor.x += glyph.metrics.advanceX * tabSize * scale;
				continue;
			}
			else if (chr == '\n')
			{
				cursor.x = 0;
				cursor.y += font.metrics.lineGap * scale;
				continue;
			}

			int x  =  glyph.metrics.offsetX + origin.x + cursor.x;
			int y  =  font.metrics.verticalOffset - glyph.metrics.offsetY + origin.y + cursor.y;
			int w  =  glyph.metrics.width;
			int h  =  glyph.metrics.height;
			int tx =  glyph.atlasPosition.x;
			int ty =  glyph.atlasPosition.y;

			sink.putRect(frect(x, y, w*scale, h*scale), frect(tx, ty, w, h), color, texture);
			cursor.x += glyph.metrics.advanceX * scale;
		}
	}

	void writef(Args...)(Font* font, Color4ub color, int scale, string fmt, Args args)
	{
		import std.format : formattedWrite;
		formattedWrite(TextRendererAppender(&this, font, color, scale), fmt, args);
	}

	void writef(Args...)(Font* font, Color4ub color, string fmt, Args args)
	{
		import std.format : formattedWrite;
		formattedWrite(TextRendererAppender(&this, font, color), fmt, args);
	}
}
