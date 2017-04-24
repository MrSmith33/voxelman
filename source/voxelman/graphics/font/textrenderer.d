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
	float depth;
	Color4ub color;
	int scale = 1;

	void put(Range)(Range chars)
	{
		renderer.appendGlyphs(chars, font, depth, color, scale);
	}
}

struct TextRenderer
{
	TexturedBatch2d* sink;
	Texture texture;
	vec2 origin = vec2(0,0);
	vec2 cursor = vec2(0,0);

	uint tabSize = 4;

	void appendGlyphs(R)(R textRange, Font* font, float depth, Color4ub color, int scale = 1)
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

			float x  = glyph.metrics.offsetX + origin.x + cursor.x;
			float y  = font.metrics.verticalOffset - glyph.metrics.offsetY + origin.y + cursor.y;
			float w  = glyph.metrics.width;
			float h  = glyph.metrics.height;
			float tx = glyph.atlasPosition.x;
			float ty = glyph.atlasPosition.y;

			sink.putRect(frect(x, y, w*scale, h*scale), frect(tx, ty, w, h), depth, color, texture);
			cursor.x += glyph.metrics.advanceX * scale;
		}
	}

	void writef(Args...)(Font* font, float depth, Color4ub color, int scale, string fmt, Args args)
	{
		import std.format : formattedWrite;
		formattedWrite(TextRendererAppender(&this, font, depth, color, scale), fmt, args);
	}

	void writef(Args...)(Font* font, float depth, Color4ub color, string fmt, Args args)
	{
		import std.format : formattedWrite;
		formattedWrite(TextRendererAppender(&this, font, depth, color), fmt, args);
	}
}
