/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.graphics.font.textmesher;

import voxelman.math;
import voxelman.graphics;
import voxelman.graphics.font.font;

/// Output range for use with formattedWrite, etc
struct TextMesherSink
{
	TextMesherParams!TextRectSink params;

	void put(Range)(Range chars)
	{
		meshText(params, chars);
	}
}

/// Sink for glyps that uses TexturedBatch2d internally
struct TextRectSink
{
	TexturedBatch2d* sink;
	Texture texture;

	void putRect(frect target, frect source, float depth, Color4ub color)
	{
		sink.putRect(target, source, depth, color, texture);
	}
}

struct StatefullTextMesher
{
	TextMesherParams!TextRectSink params;

	this(TexturedBatch2d* texturedBatch, Texture texture)
	{
		params.sink = TextRectSink(texturedBatch, texture);
	}
	//this(TexturedBatch2d* texturedBatch, Texture texture, )

	void meshText(R)(auto ref R textRange)
	{
		.meshText(params, textRange);
	}

	void meshTextf(Args...)(string fmt, Args args)
	{
		import std.format : formattedWrite;
		formattedWrite(TextMesherSink(params), fmt, args);
	}
/*
	void meshTextf(Args...)(Font* font, float depth, Color4ub color, int scale, string fmt, Args args)
	{
		import std.format : formattedWrite;
		formattedWrite(TextMesherSink(&this, font, depth, color, scale), fmt, args);
	}

	void meshTextf(Args...)(Font* font, float depth, Color4ub color, string fmt, Args args)
	{
		import std.format : formattedWrite;
		formattedWrite(TextMesherSink(&this, font, depth, color), fmt, args);
	}*/
}

struct TextMesherParams(Sink)
{
	Sink sink;
	FontRef font;
	vec2 origin = vec2(0,0);
	vec2 cursor = vec2(0,0);
	float depth = 0;
	Color4ub color = Colors.black;
	int scale = 1;
	int tabSize = 4;
}

void meshText(P, R)(ref P params, R textRange)
{
	foreach(dchar chr; textRange)
	{
		Glyph* glyph = params.font.getGlyph(chr);

		switch(chr) // special chars
		{
			case ' ':
				params.cursor.x += glyph.metrics.advanceX * params.scale;
				continue;
			case '\t':
				params.cursor.x += glyph.metrics.advanceX * params.tabSize * params.scale;
				continue;
			case '\n':
				params.cursor.x = 0;
				params.cursor.y += params.font.metrics.lineGap * params.scale;
				continue;
			default: break;
		}

		float x  = params.origin.x + params.cursor.x + glyph.metrics.offsetX;
		float y  = params.origin.y + params.cursor.y + params.font.metrics.verticalOffset - glyph.metrics.offsetY;
		float w  = glyph.metrics.width;
		float h  = glyph.metrics.height;
		float tx = glyph.atlasPosition.x;
		float ty = glyph.atlasPosition.y;

		params.sink.putRect(frect(x, y, w*params.scale, h*params.scale), frect(tx, ty, w, h), params.depth, params.color);
		params.cursor.x += glyph.metrics.advanceX * params.scale;
	}
}
