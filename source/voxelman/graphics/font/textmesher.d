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
	size_t numRectsPutted;

	void putRect(frect target, frect source, float depth, Color4ub color)
	{
		++numRectsPutted;
		sink.putRect(target, source, depth, color, texture);
	}

	void applyOffset(vec2 offset)
	{
		sink.addOffsetToLastRects(offset, numRectsPutted);
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
	int column; // ref

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

	void meshGlyph(Glyph* glyph)
	{
		int w = glyph.metrics.width;
		int h = glyph.metrics.height;

		int offsetX = params.monospaced ? glyph.metrics.offsetX : 0;
		int x = params.origin.x + params.cursor.x + offsetX * params.scale;
		int y = params.origin.y + params.cursor.y + (params.font.metrics.ascent - glyph.metrics.offsetY) * params.scale;

		auto geometryRect = frect(x, y, w * params.scale, h * params.scale);
		auto atlasRect = frect(glyph.atlasPosition.x, glyph.atlasPosition.y, w, h);

		bool shouldDraw = clipTexturedRect(geometryRect, atlasRect, params.scissors);

		if (shouldDraw)
		{
			TextStyle style = params.styles[styleRange.front];
			params.sink.putRect(geometryRect, atlasRect, params.depth, style.color);//params.color);
		}
	}

	void updateMaxWidth() {
		params.size.x = max(params.size.x, params.cursor.x);
	}

	int singleGlyphWidth  = params.font.metrics.width  * params.scale;
	int singleGlyphHeight = params.font.metrics.height * params.scale;
	int advanceX = params.font.metrics.advanceX * params.scale;
	int advanceY = params.font.metrics.advanceY * params.scale;

	foreach(dchar codePoint; textRange.byDchar)
	{
		switch(codePoint) // special chars
		{
			case ' ':
				params.cursor.x += advanceX;
				++params.column;
				continue;
			case '\t':
				int tabGlyphs = tabWidth(params.tabSize, params.column);
				params.cursor.x += advanceX * tabGlyphs;
				params.column += tabGlyphs;
				continue;
			case '\n':
				updateMaxWidth();
				params.cursor.x = 0;
				params.cursor.y += advanceY;
				params.column = 0;
				continue;
			case '\r':
				continue;
			default:
				++params.column;
				break;
		}

		Glyph* glyph = params.font.getGlyph(codePoint);
		static if (mesh) meshGlyph(glyph);

		int glyphAdvanceX = params.monospaced ? advanceX : glyph.metrics.advanceX;
		params.cursor.x += glyphAdvanceX * params.scale;
		static if (mesh) styleRange.popFront;
	}

	params.size.y = max(params.size.y, params.cursor.y + singleGlyphHeight);
	updateMaxWidth();
}

/// Changes params size and cursor
void measureText(P, T)(ref P params, T textRange)
{
	meshText!(false)(params, textRange);
}

int tabWidth(int tabSize, int column)
{
	return tabSize - column % tabSize;
}

enum Alignment
{
	min,
	center,
	max
}

/// Applies offset to all previously meshed glyphs
/// Number of meshed glyphs is taken from TextRectSink
void alignMeshedText(P)(ref P params, Alignment halign = Alignment.min, Alignment valign = Alignment.min, ivec2 area = ivec2(0,0))
{
	if (halign == Alignment.min && valign == Alignment.min) return;

	ivec2 alignmentOffset = textAlignmentOffset(ivec2(params.size), halign, valign, area);
	params.sink.applyOffset(vec2(alignmentOffset));
	params.origin += alignmentOffset;
}

// modifies cursor to be aligned for passed text
void meshTextAligned(P, T)(ref P params, T textRange, Alignment halign = Alignment.min, Alignment valign = Alignment.min)
{
	if (halign == Alignment.min && valign == Alignment.min) {
		meshText!(true)(params, textRange);
		return;
	}

	auto origin = params.origin;
	auto size = params.size;
	auto cursor = params.cursor;
	measureText(params, textRange);
	auto alignmentOffset = textAlignmentOffset(ivec2(params.size), halign, valign);
	params.origin = origin + alignmentOffset;
	params.cursor = cursor;
	meshText!(true)(params, textRange);
}

ivec2 textAlignmentOffset(ivec2 textSize, Alignment halign, Alignment valign, ivec2 area = ivec2(0,0))
{
	ivec2 offset;
	final switch (halign)
	{
		case Alignment.min: offset.x = 0; break;
		case Alignment.center: offset.x = area.x/2 - textSize.x/2; break;
		case Alignment.max: offset.x = area.x - textSize.x; break;
	}
	final switch (valign)
	{
		case Alignment.min: offset.y = 0; break;
		case Alignment.center: offset.y = area.y/2 - textSize.y/2; break;
		case Alignment.max: offset.y = area.y - textSize.y; break;
	}
	return offset;
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
