/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.gui.textedit.texteditor;

import std.stdio : writefln, writeln;

import voxelman.container.buffer;
import voxelman.container.chunkedrange;
import voxelman.graphics;
import voxelman.gui;
import voxelman.math;
import voxelman.platform;
import voxelman.text.linebuffer;
import voxelman.text.scale;

import voxelman.gui.textedit.cursor;
import voxelman.gui.textedit.linebuffer;
import voxelman.gui.textedit.textbuffer;
import voxelman.gui.textedit.undostack;
import voxelman.gui.textedit.textmodel;

alias lvec2 = Vector!(long, 2);

// update - called after size is optionally changed
// render - called after all updates

enum HighlightStyle
{
	text,
	number
}

struct StyleSlice
{
	HighlightStyle style;
	uint length;
}

TextEditor loadFileAsDocument(string filename = "test.txt")
{
	import std.file : read, exists;
	import std.path : absolutePath;

	string textData;

	if (exists(filename))
	{
		writefln("load %s", absolutePath(filename));
		textData = cast(string)read(filename);
	}
	else
	{
		writeln("new empty file");
	}

	return createTextEditor(textData, filename);
}

TextEditor createTextEditor(string textData = null, string filename = null)
{
	return TextEditor(textData, filename);
}

class EditorTextModel : TextModel
{
	TextEditorRef editor;
	this(TextEditorRef ed) { editor = ed; }
	bool isEditable() { return true; }

	int numLines() { return editor.lines.numLines; }
	int lastLine() { return editor.lines.lastLine; }
	ChunkedRange!char opSlice(ulong from, ulong to) { return editor.textData[from..to].toChunkedRange; }
	LineInfo lineInfo(int line) { return editor.lines.lineInfo(line); }

	void onCommand(EditorCommand com) { editor.onCommand(com); }
	void replaceSelection(const(char)[] str) { editor.replaceSelection(str); }
	ref Selection selection() { return editor.selection; }
	//ivec2 textSizeInGlyphs() { return editor.textSizeInGlyphs; }
	void moveSelectionCursor(MoveCommand com, bool extendSelection) { editor.moveSelectionCursor(com, extendSelection); }
}

/// Default constructed TextEditor is not valid. Use constructor
alias TextEditorRef = TextEditor*;
struct TextEditor
{
	// text data
	private PieceTable textData;
	private string filename;
	private LineInfoBuffer lines;
	private ivec2 textSizeInGlyphs;
	private Selection selection;
	mixin ReadHelpers!();
	mixin WriteHelpers!();

	this(string textData, string filename)
	{
		this.textData = textData;
		this.filename = filename;
		textSizeInGlyphs.y = lines.calc(textData);
		textSizeInGlyphs.x = lines.maxLineSize;
	}

	void onCommand(EditorCommand com)
	{
		switch(com.type)
		{
			case EditorCommandType.insert_eol:
				replaceSelection("\n");
				break;
			case EditorCommandType.insert_tab:
				replaceSelection("\t");
				break;
			case EditorCommandType.delete_left_char:
				if (selection.empty)
				{
					auto leftCur = moveCursor(selection.end, MoveCommand.move_left_char);
					removeAndUpdateSelection(Selection(leftCur, selection.end));
				}
				else removeAndUpdateSelection(selection);
				break;
			case EditorCommandType.delete_left_word:

				break;
			case EditorCommandType.delete_left_line:

				break;
			case EditorCommandType.delete_right_char:
				if (selection.empty)
				{
					auto rightCur = moveCursor(selection.end, MoveCommand.move_right_char);
					removeAndUpdateSelection(Selection(selection.end, rightCur));
				}
				else removeAndUpdateSelection(selection);
				break;
			case EditorCommandType.delete_right_word:
				break;
			case EditorCommandType.delete_right_line:
				break;
			case EditorCommandType.cut:
				cutSelection();
				break;
			case EditorCommandType.copy:
				copySelection();
				break;
			case EditorCommandType.paste:
				//MonoTime pasteStart = MonoTime.currTime;
				auto str = clipboard;
				replaceSelection(str);
				//writefln("pasted %sB in %ss",
				//	scaledNumberFmt(str.length),
				//	scaledNumberFmt(MonoTime.currTime-pasteStart));
				break;
			case EditorCommandType.select_all:
				selection = Selection(Cursor(0,0), Cursor(lines.textEnd, lines.lastLine));
				break;
			case EditorCommandType.undo:
				undo();
				break;
			case EditorCommandType.redo:
				redo();
				break;
			default:
				break;
		}
	}
}

mixin template ReadHelpers()
{
	//import std.datetime : MonoTime;
	import std.utf : stride, strideBack;
	import std.stdio : writefln, writeln;
	import voxelman.text.scale;
	// uses
	// T textData;
	// L lines;
	// Selection selection;

	void delegate(string) setClipboard;
	void clipboard(S)(S str) {
		if (!setClipboard) return;
		import std.experimental.allocator.mallocator;
		auto buf = cast(char[])Mallocator.instance.allocate(str.length+1);
		buf[str.length] = '\0';
		str.copyInto(buf[0..str.length]);
		//auto t1 = MonoTime.currTime;
		setClipboard(cast(string)buf[0..str.length]);
		//auto t2 = MonoTime.currTime;
		Mallocator.instance.deallocate(buf);
		//writefln("clipboard copy %ss", scaledNumberFmt(t2 - t1));
	}

	void moveSelectionCursor(MoveCommand com, bool extendSelection)
	{
		selection.end = moveCursor(selection.end, com);
		if (!extendSelection) selection.start = selection.end;
	}

	void copySelection()
	{
		auto sel = getSelectionForCopyCut();
		writefln("copy %s %s", sel.start.byteOffset, sel.end.byteOffset);
		copyText(sel.start.byteOffset, sel.end.byteOffset);
	}

	void copyText(ulong from, ulong to)
	{
		//MonoTime copyStart = MonoTime.currTime;
		auto copiedText = textData[from..to].toChunkedRange.byItem;

		clipboard = copiedText;

		////MonoTime copyEnd =// MonoTime.currTime;
		//writefln("copied %sB in %ss", scaledNumberFmt(copiedText.length), scaledNumberFmt(copyEnd-copyStart));
	}

	Selection getSelectionForCopyCut()
	{
		if (selection.empty)
		{
			// select whole line
			auto line = selection.end.line;
			auto info = lines[line];
			return Selection(Cursor(info.startOffset, line),
				Cursor(info.nextStartOffset, line));
		}
		else
			return selection.normalized;
	}

	uint strideAt(ulong offset)
	{
		auto str = textData[offset..$];
		return stride(str);
	}

	ulong nextOffset(ulong offset)
	{
		return offset + strideAt(offset);
	}

	ulong prevOffset(ulong offset)
	{
		return offset - strideBack(textData[0..offset]);
	}

	Cursor moveCursor(Cursor cur, MoveCommand com)
	{
		auto lineInfo = lines.lineInfo(cur.line);

		final switch(com) with(MoveCommand)
		{
		case move_right_char:
			if (cur.byteOffset == lineInfo.endOffset)
			{
				if (cur.line < lines.lastLine)
				{
					++cur.line;
					cur.byteOffset = lineInfo.nextStartOffset;
				}
			}
			else
			{
				auto newOffset = nextOffset(cur.byteOffset);
				cur.byteOffset = newOffset;
			}
			break;
		case move_right_word:
			break;
		case move_left_char:
			if (cur.byteOffset == lineInfo.startOffset)
			{
				if (cur.line > 0)
				{
					--cur.line;
					cur.byteOffset = lines.lineEndOffset(cur.line);
				}
			}
			else
			{
				auto newOffset = prevOffset(cur.byteOffset);
				cur.byteOffset = newOffset;
			}
			break;
		case move_left_word:
			break;
		case move_up_line:
			if (cur.line > 0)
			{
				--cur.line;
				cur.byteOffset = lines.lineStartOffset(cur.line);
			}
			break;
		case move_up_page:
			break;
		case move_down_line:
			if (cur.line < lines.lastLine)
			{
				++cur.line;
				cur.byteOffset = lineInfo.nextStartOffset;
			}
			break;
		case move_down_page:
			break;
		case move_to_bol:
			cur.byteOffset = lineInfo.startOffset;
			break;
		case move_to_eol:
			cur.byteOffset = lineInfo.endOffset;
			break;
		}
		return cur;
	}
}

mixin template WriteHelpers()
{
	//import std.datetime : MonoTime;
	// uses
	// T textData;
	// L lines;
	// ReadHelpers;

	private UndoStack!UndoItem undoStack;

	string delegate() getClipboard;
	string clipboard() { if (getClipboard) return getClipboard(); else return null; }

	private void cutSelection()
	{
		auto sel = getSelectionForCopyCut();
		copyText(sel.start.byteOffset, sel.end.byteOffset);
		removeAndUpdateSelection(sel);
	}

	void replaceSelection(const(char)[] str)
	{
		removeAndUpdateSelection(selection);
		selection = emptySelection(insertText(selection.end, str));
	}

	/// Returns pos after inserted text
	Cursor insertText(Cursor cur, const(char)[] str)
	{
		if (str.length == 0) return cur;

		auto pieceUndo = textData.insert(cur.byteOffset, str);
		int insertedLines = lines.onPaste(cur, str);
		auto afterInsertedText = Cursor(cur.byteOffset + str.length, cur.line + insertedLines);
		auto undoItem = UndoItem(pieceUndo, cur, afterInsertedText, UndoCommand.undoInsert, selection);
		putUndo(undoItem);
		return afterInsertedText;
	}

	void removeAndUpdateSelection(Selection sel)
	{
		Selection normSel = sel.normalized;
		removeText(normSel);
		// position cursor at the start of removed text
		selection = emptySelection(normSel.start);
	}

	void removeText(Selection sel)
	{
		removeText(sel.start, sel.end);
	}

	void removeText(Cursor from, Cursor to)
	{
		if (from == to) return;
		auto pieceUndo = textData.remove(from.byteOffset, to.byteOffset-from.byteOffset);
		auto undoItem = UndoItem(pieceUndo, from, to, UndoCommand.undoRemove, selection);
		putUndo(undoItem);
		lines.onRemove(from, to);
	}

	enum UndoCommand
	{
		undoInsert,
		undoRemove
	}

	private static struct UndoItem
	{
		PieceRestoreRange pieceUndo;
		Cursor from;
		Cursor to;
		UndoCommand undoCom;
		Selection selectionUndo;
		bool group; // Piece ranges in one group have the same flag
	}

	private UndoItem onUndoRedoAction(UndoItem undoItem)
	{
		// undo text operation
		undoItem.pieceUndo = undoItem.pieceUndo.apply(textData.pieces.length);

		// undo line buffer operation
		final switch (undoItem.undoCom)
		{
			case UndoCommand.undoInsert:
				lines.onRemove(undoItem.from, undoItem.to);
				// now create undoRemove command
				undoItem.undoCom = UndoCommand.undoRemove;
				break;

			case UndoCommand.undoRemove:
				// this needs to happen after text undo, since it passes inserted text to line cache
				lines.onPaste(undoItem.from, textData[undoItem.from.byteOffset..undoItem.to.byteOffset]);
				// now create repeat remove command
				undoItem.undoCom = UndoCommand.undoInsert;
				break;
		}

		// collect current cursor info
		Selection currentSel = selection;
		// restore cursor
		selection = undoItem.selectionUndo;
		// store cursor undo
		undoItem.selectionUndo = currentSel;

		return undoItem;
	}

	private void putUndo(UndoItem undoItem)
	{
		undoStack.commitUndoItem(undoItem);
	}

	void undo()
	{
		undoStack.undo(&onUndoRedoAction);
	}

	void redo()
	{
		undoStack.redo(&onUndoRedoAction);
	}
}

unittest
{
	TextEditor ed = createTextEditor("aaaa");

	assert(ed.lines.textEnd == 4);

	// Test single char insert
	ed.selection = emptySelection(Cursor(2, 0));
	ed.replaceSelection("b");
	assert(ed.lines.textEnd == 5);
	assert(ed.lines.numLines == 1);
	assert(ed.textData[].equalDchars("aabaa"));
	assert(ed.selection == emptySelection(Cursor(3, 0)));

	// Test newline insert
	ed.replaceSelection("\n");
	assert(ed.lines.textEnd == 6);
	assert(ed.lines.numLines == 2);
	assert(ed.textData[].equalDchars("aab\naa"));
	assert(ed.selection == emptySelection(Cursor(4, 1)));
}

unittest
{
	TextEditor ed = createTextEditor();

	assert(ed.lines.lastLine == 0);
	assert(ed.lines.textEnd == 0);
	assert(ed.lines.numLines == 1);

	// Test insert in empty file
	ed.replaceSelection("a");
	assert(ed.lines.textEnd == 1);
	assert(ed.lines.numLines == 1);
	assert(ed.lines.lastLine == 0);
	assert(ed.textData[].equalDchars("a"));
	assert(ed.selection == emptySelection(Cursor(1, 0)));

	ed.replaceSelection("b");
	assert(ed.lines.textEnd == 2);
	assert(ed.lines.numLines == 1);
	assert(ed.lines.lastLine == 0);
	assert(ed.textData[].equalDchars("ab"));
	assert(ed.selection == emptySelection(Cursor(2, 0)));
}

unittest
{
	TextEditor ed = createTextEditor("zz\nzz");

	assert(ed.lines.lastLine == 1);
	assert(ed.lines.textEnd == 5);
	assert(ed.lines.numLines == 2);
	assert(ed.lines[0] == LineInfo(0, 2, 1));
	assert(ed.lines[1] == LineInfo(3, 2, 1));

	// Test insert in multiline file
	ed.replaceSelection("a");
	assert(ed.lines.textEnd == 6);
	assert(ed.lines.numLines == 2);
	assert(ed.lines.lastLine == 1);
	assert(ed.textData[].equalDchars("azz\nzz"));
	assert(ed.selection == emptySelection(Cursor(1, 0)));
	assert(ed.lines[0] == LineInfo(0, 3, 1));
	assert(ed.lines[1] == LineInfo(4, 2, 1));

	// Test correct attribute update of first line
	// when inserting in col > 0
	ed.replaceSelection("b");
	assert(ed.lines.textEnd == 7);
	assert(ed.lines.numLines == 2);
	assert(ed.lines.lastLine == 1);
	assert(ed.textData[].equalDchars("abzz\nzz"));
	assert(ed.selection == emptySelection(Cursor(2, 0)));
	assert(ed.lines[0] == LineInfo(0, 4, 1));
	assert(ed.lines[1] == LineInfo(5, 2, 1));
}

unittest
{
	TextEditor ed = createTextEditor("zz\nzz");

	ed.selection = emptySelection(Cursor(1, 0));

	// Test inserting multiple lines
	ed.replaceSelection("a\nb\nc");
	assert(ed.lines.textEnd == 10);
	assert(ed.lines.numLines == 4);
	assert(ed.lines.lastLine == 3);
	assert(ed.textData[].equalDchars("za\nb\ncz\nzz"));
	assert(ed.selection == emptySelection(Cursor(6, 2)));
	assert(ed.lines[0] == LineInfo(0, 2, 1));
	assert(ed.lines[1] == LineInfo(3, 1, 1));
	assert(ed.lines[2] == LineInfo(5, 2, 1));
	assert(ed.lines[3] == LineInfo(8, 2, 1));
}

unittest
{
	TextEditor ed = createTextEditor("abcd");

	ed.selection = Selection(Cursor(1, 0), Cursor(3, 0));
	ed.removeAndUpdateSelection(ed.selection);

	assert(ed.selection == emptySelection(Cursor(1, 0)));
	assert(ed.textData[].equalDchars("ad"));
}

// Test undo of text, cursor and line cache
unittest
{
	TextEditor ed = createTextEditor();

	assert(ed.lines.textEnd == 0);
	assert(ed.textData[].equalDchars(""));
	assert(ed.selection == emptySelection(Cursor(0, 0)));

	ed.replaceSelection("a");

	assert(ed.lines.textEnd == 1);
	assert(ed.textData[].equalDchars("a"));
	assert(ed.selection == emptySelection(Cursor(1, 0)));

	ed.undo();

	assert(ed.lines.textEnd == 0);
	assert(ed.textData[].equalDchars(""));
	assert(ed.selection == emptySelection(Cursor(0, 0)));

	ed.redo();

	assert(ed.lines.textEnd == 1);
	assert(ed.textData[].equalDchars("a"));
	assert(ed.selection == emptySelection(Cursor(1, 0)));
}
