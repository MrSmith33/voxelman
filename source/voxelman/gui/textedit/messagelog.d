/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.gui.textedit.messagelog;

import voxelman.math;
import voxelman.container.chunkedbuffer;
import voxelman.gui.textedit.cursor;
import voxelman.gui.textedit.textmodel;
import voxelman.gui.textedit.linebuffer;
import voxelman.gui.textedit.texteditor;

class MessageLogTextModel : TextModel
{
	MessageLog* text;

	this(MessageLog* text) { this.text = text; }
	bool isEditable() { return false; }

	int numLines() { return text.lines.numLines; }
	int lastLine() { return text.lines.lastLine; }
	ChunkedRange!char opSlice(ulong from, ulong to) { return (*text)[from..to]; }
	LineInfo lineInfo(int line) { return text.lineInfo(line); }

	void onCommand(EditorCommand com) { text.onCommand(com); }
	void replaceSelection(const(char)[] str) {}
	ref Selection selection() { return text.selection; }
	//ivec2 textSizeInGlyphs() { return ivec2(0,0); }
	void moveSelectionCursor(MoveCommand com, bool extendSelection)
	{
		text.selection.end = text.moveCursor(text.selection.end, com);
		if (!extendSelection) text.selection.start = text.selection.end;
	}
}

struct MessageLog
{
	import std.format : formattedWrite;
	private ChunkedBuffer!(char, 4096) textData;
	private LineInfoBuffer lines;
	Selection selection;
	mixin ReadHelpers!();

	this(string text)
	{
		textData.put(text);
		lines.calc(text);
	}

	ulong length() { return textData.length; }
	alias opDollar = length;
	LineInfo lineInfo(int line) { return lines.lineInfo(line); }

	ChunkedRange!char opSlice(ulong from, ulong to)
	{
		return textData[from..to].toChunkedRange;
	}

	void onCommand(EditorCommand com)
	{
		switch(com)
		{
			case EditorCommand.copy:
				copySelection();
				break;
			case EditorCommand.select_all:
				selection = Selection(Cursor(0,0), Cursor(lines.textEnd, lines.lastLine));
				break;
			default:
				break;
		}
	}

	void clear()
	{
		lines.clear();
		textData.clear();
		selection = Selection();
	}

	void put(in char[] str)
	{
		textData.put(str);
		lines.onPaste(Cursor(lines.textEnd, lines.lastLine), str);
	}

	void putf(Args...)(const(char)[] fmt, Args args)
	{
		formattedWrite(&this, fmt, args);
	}

	void putfln(Args...)(const(char)[] fmt, Args args)
	{
		formattedWrite(&this, fmt, args);
		put("\n");
	}

	void putln(const(char)[] str)
	{
		put(str);
		put("\n");
	}
}

unittest
{
	import std.algorithm : equal;
	import std.stdio;
	MessageLog log;
	log.putln("test1");
	log.putln("test2");
	log.putln("test3");

	auto from = log.lineInfo(1).startOffset;
	auto to = log.lineInfo(2).endOffset;
	auto text = log[from..to].byItem;

	assert(text.equal("test2\ntest3"));
}
