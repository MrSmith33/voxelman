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
	TextRectSink sink;
	FontRef font;
	ivec2 origin = ivec2(0,0);
	ivec2 cursor = ivec2(0,0);
	irect scissors = irect(-int.max/2, -int.max/2, int.max, int.max);
	float depth = 0;
	Color4ub color = Colors.black;
	int scale = 1;
	int tabSize = 4;
	bool monospaced = false;
}

/// Modifies params.cursor and params.sink
void meshText(P, R)(ref P params, R textRange)
{
	foreach(ubyte chr; textRange)
	{
		Glyph* glyph = params.font.getGlyph(chr);

		int glyphAdvanceX = params.monospaced ? params.font.metrics.monoAdvanceX : glyph.metrics.advanceX;

		switch(chr) // special chars
		{
			case ' ':
				params.cursor.x += glyphAdvanceX * params.scale;
				continue;
			case '\t':
				params.cursor.x += glyphAdvanceX * params.tabSize * params.scale;
				continue;
			case '\n':
				params.cursor.x = 0;
				params.cursor.y += params.font.metrics.lineGap * params.scale;
				continue;
			default: break;
		}

		int x = params.origin.x + params.cursor.x + glyph.metrics.offsetX;
		int y = params.origin.y + params.cursor.y + params.font.metrics.verticalOffset - glyph.metrics.offsetY;

		int w = glyph.metrics.width;
		int h = glyph.metrics.height;

		auto geometryRect = frect(x, y, w * params.scale, h * params.scale);
		auto atlasRect = frect(glyph.atlasPosition.x, glyph.atlasPosition.y, w, h);

		bool shouldDraw = clipTexturedRect(geometryRect, atlasRect, params.scissors);

		if (shouldDraw)
		{
			params.sink.putRect(geometryRect, atlasRect, params.depth, params.color);
		}

		params.cursor.x += glyphAdvanceX * params.scale;
	}
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
