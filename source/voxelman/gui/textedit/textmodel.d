/**
Copyright: Copyright (c) 2017-2018 Andrey Penechko.
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
	ChunkedRange!char opSlice(size_t from, size_t to);
	LineInfo lineInfo(int line);

	void onCommand(EditorCommand com);
	ref Selection selection();
	//ivec2 textSizeInGlyphs();
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
	Color4ub color = Colors.black;

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

enum EditorCommandType
{
	none, // convertor function returns this if nothing matches

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

	input,

	select_all,

	undo,
	redo,

	cur_move_first,
	cur_move_right_char = cur_move_first,
	cur_move_right_word,
	cur_move_left_char,
	cur_move_left_word,
	cur_move_up_line,
	cur_move_up_page,
	cur_move_down_line,
	cur_move_down_page,
	cur_move_to_bol,
	cur_move_to_eol,
	cur_move_last = cur_move_to_eol,
}

enum EditorCommandFlags
{
	extendSelection = 1, //
}

struct EditorCommand
{
	EditorCommandType type;
	uint flags; // set of EditorCommandFlags
	const(char)[] inputText; // must be copied when handling command

	bool extendSelection() {
		return (flags & EditorCommandFlags.extendSelection) != 0;
	}

	MoveCommand toMoveCommand()
	{
		assert(type >= EditorCommandType.cur_move_first);
		assert(type <= EditorCommandType.cur_move_last);

		return cast(MoveCommand)(type - EditorCommandType.cur_move_first);
	}
}
