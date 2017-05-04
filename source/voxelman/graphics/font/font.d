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
	int offsetX;
	int offsetY;
	uint advanceX;
	uint advanceY;
}

struct FontMetrics
{
	uint height;
	uint size;
	uint lineGap;
	uint ascender;
	uint descender;
	uint monoAdvanceX;
	int  verticalOffset; // Can be used to manually adjust vertical position of text.
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
		if (auto glyph = chr in glyphs)
		{
			return glyph;
		}
		else
			return '?' in glyphs;//TODO: Add loading for nonexisting glyphs
	}

	void sanitize()
	{
		metrics.monoAdvanceX = max(metrics.monoAdvanceX, 1);
		metrics.lineGap = max(metrics.lineGap, 1);
	}

	string filename;
	FontMetrics metrics;
	Glyph[dchar] glyphs;

	int[dchar][dchar] kerningTable;
	bool kerningEnabled = true;
}

alias FontRef = Font*;
