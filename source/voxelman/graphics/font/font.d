/**
Copyright: Copyright (c) 2013-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.graphics.font.font;

import voxelman.math;

struct Glyph
{
	ivec2 atlasPosition;
	GlyphMetrics metrics;
}

struct GlyphMetrics
{
	uint width;
	uint height;
	int  offsetX; // bearingX
	int  offsetY; // bearingY
	uint advanceX;
	uint advanceY;
}

struct FontMetrics
{
	uint width; // monospaced width
	uint height; // max glyph height
	uint ascent; // vertical offset from baseline to highest point (positive)
	uint descent; // vertical offset from baseline to lowest point (negative)
	uint advanceX; // mono width + glyph spacing
	uint advanceY; // max glyph height + line spacing
}

struct Font
{
	int getKerning(in dchar leftGlyph, in dchar rightGlyph)
	{
		int[dchar] rightGlyps = *(leftGlyph in kerningTable);
		int kerning = *(rightGlyph in rightGlyps);
		return kerning;
	}

	Glyph* getGlyph(in dchar chr)
	{
		import std.utf : replacementDchar;
		if (auto glyph = chr in glyphs)
		{
			return glyph;
		}
		else
			return replacementDchar in glyphs;
	}

	void sanitize()
	{
		metrics.width = max(metrics.width, 1);
		metrics.height = max(metrics.height, 1);
	}

	string filename;
	FontMetrics metrics;
	Glyph[dchar] glyphs;

	int[dchar][dchar] kerningTable;
	bool kerningEnabled = false;
}

alias FontRef = Font*;
