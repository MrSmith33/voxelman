/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.gui.textedit.textmodel;

public import voxelman.gui.textedit.linebuffer : LineInfo;
public import voxelman.container.chunkedrange;
public import voxelman.gui.textedit.cursor;
import voxelman.math;
import voxelman.graphics;

interface TextModel
{
	bool isEditable();

	int numLines();
	int lastLine();
	ChunkedRange!char opSlice(ulong from, ulong to);
	LineInfo lineInfo(int line);

	void onCommand(EditorCommand com);
	void replaceSelection(const(char)[] str);
	ref Selection selection();
	//ivec2 textSizeInGlyphs();
	void moveSelectionCursor(MoveCommand com, bool extendSelection);
}

Selection emptySelection(Cursor cur) { return Selection(cur, cur); }

struct Selection
{
	Cursor start;
	Cursor end;

	/// Returns selection where start <= end
	Selection normalized()
	{
		if (start.byteOffset < end.byteOffset)
			return Selection(start, end);
		else
			return Selection(end, start);
	}

	bool empty()
	{
		return start.byteOffset == end.byteOffset;
	}
}

alias TextViewSettingsRef = TextViewSettings*;
struct TextViewSettings
{
	// visual
	FontRef font;
	int fontScale = 1;
	int tabSize = 4;
	bool monospaced = true;

	ivec2 scaledGlyphSize() const { return ivec2(scaledGlyphW, scaledGlyphH); }
	int scaledGlyphW() const { return font.metrics.advanceX * fontScale; }
	int scaledGlyphH() const { return font.metrics.advanceY * fontScale; }

	// scrolling
	int scrollSpeedLines = 3;

	this(FontRef font)
	{
		this.font = font;
	}
}

enum EditorCommand
{
	insert_eol,
	insert_tab,
	delete_left_char,
	delete_left_word,
	delete_left_line,
	delete_right_char,
	delete_right_word,
	delete_right_line,

	cut,
	copy,
	paste,

	select_all,

	undo,
	redo,
}
