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
	TextMesherParams* params;

	void put(Range)(Range chars)
	{
		meshText(*params, chars);
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

struct TextMesherParams
{
	TextRectSink sink; // ref
	FontRef font;
	ivec2 origin = ivec2(0, 0);
	ivec2 cursor = ivec2(0, 0); // ref
	irect scissors = irect(-int.max/2, -int.max/2, int.max, int.max);
	float depth = 0;
	Color4ub color = Colors.black;
	int scale = 1;
	int tabSize = 4;
	bool monospaced = false;
	TextStyle[] styles;

	// ref
	vec2 size = vec2(0, 0); // size of text relative to origin
}

struct TextStyle
{
	Color4ub color = Colors.black;
}

alias StyleId = ubyte;

/// Modifies params.cursor and params.sink
void meshText(bool mesh = true, P, T)(ref P params, T textRange)
{
	import std.range : repeat;
	TextStyle[1] styles = [TextStyle(params.color)];
	auto prevStyles = params.styles;
	params.styles = styles[];
	meshText!(mesh)(params, textRange, repeat(StyleId(0)));
	params.styles = prevStyles;
}

struct StyledCodePoint
{
	dchar codepoint;
	TextStyle style;
}

struct TextStyleZip(T, S)
{
	T textRange;
	S styleRange;

	bool empty()
	{
		return textRange.empty || styleRange.empty;
	}

	StyledCodePoint front()
	{
		return StyledCodePoint(textRange.front, styleRange.front);
	}

	void popFront()
	{
		textRange.popFront;
		styleRange.popFront;
	}
}

/// ditto
void meshText(bool mesh = true, P, T, S)(ref P params, T textRange, S styleRange)
{
	import std.uni;
	import std.utf;

	foreach(dchar codePoint; textRange.byDchar)
	{
		static if (mesh) TextStyle style = params.styles[styleRange.front];
		Glyph* glyph = params.font.getGlyph(codePoint);

		int glyphAdvanceX = params.monospaced ? params.font.metrics.width+2 : glyph.metrics.advanceX;

		switch(codePoint) // special chars
		{
			case ' ':
				params.cursor.x += glyphAdvanceX * params.scale;
				continue;
			case '\t':
				params.cursor.x += glyphAdvanceX * params.tabSize * params.scale;
				continue;
			case '\n':
				params.cursor.x = 0;
				params.cursor.y += (params.font.metrics.height+1) * params.scale;
				continue;
			case '\r':
				continue;
			default: break;
		}

		static if (mesh)
		{
			int x = params.origin.x + params.cursor.x + glyph.metrics.offsetX * params.scale;
			int y = params.origin.y + params.cursor.y + (params.font.metrics.ascent - glyph.metrics.offsetY) * params.scale;

			int w = glyph.metrics.width;
			int h = glyph.metrics.height;

			auto geometryRect = frect(x, y, w * params.scale, h * params.scale);
			auto atlasRect = frect(glyph.atlasPosition.x, glyph.atlasPosition.y, w, h);

			bool shouldDraw = clipTexturedRect(geometryRect, atlasRect, params.scissors);

			if (shouldDraw)
			{
				params.sink.putRect(geometryRect, atlasRect, params.depth, style.color);//params.color);
			}
		}

		params.cursor.x += glyphAdvanceX * params.scale;
		params.size.x = max(params.size.x, params.cursor.x);
		static if (mesh) styleRange.popFront;
	}

	params.size.y = max(params.size.y, params.cursor.y);
}

void measureText(P, T)(ref P params, T textRange)
{
	meshText!(false)(params, textRange);
}


// returns true if rect is visible
bool clipTexturedRect(ref frect geometryRect, ref frect atlasRect, irect scissors)
{
	frect intersection = rectIntersection(geometryRect, frect(scissors));
	if (intersection.empty) return false;

	if (intersection == geometryRect) return true;

	vec2 newEnd = intersection.endPosition;
	vec2 newSize = intersection.size;

	vec2 sizeRescaleMult = newSize / geometryRect.size; // [0; 1]
	vec2 absStartOffset = intersection.position - geometryRect.position;
	vec2 relativeStartOffset = absStartOffset / geometryRect.size; // [0; 1]
	vec2 atlasPosOffset = relativeStartOffset * atlasRect.size; // old atlas size

	atlasRect.size *= sizeRescaleMult;
	atlasRect.position += atlasPosOffset;

	geometryRect = intersection;

	return true;
}

void meshTextf(P, Args...)(ref P params, string fmt, Args args)
{
	import std.format : formattedWrite;
	formattedWrite(TextMesherSink(&params), fmt, args);
}
