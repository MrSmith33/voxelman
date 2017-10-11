/**
Copyright: Copyright (c) 2014-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.gui.textedit.undostack;

import voxelman.container.chunkedbuffer;

struct UndoStack(Item)
{
	private ChunkedBuffer!Item _undoStack;
	private ChunkedBuffer!Item _redoStack;
	private bool _currentGroup;
	private bool _isGrouping = false;

	void beginGroup()
	{
		_currentGroup = !_currentGroup;
		_isGrouping = true;
	}

	void endGroup()
	{
		_isGrouping = false;
	}

	void commitUndoItem(Item item)
	{
		if (!_isGrouping)
		{
			_currentGroup = !_currentGroup;
		}

		item.group = _currentGroup;
		_undoStack.putBack(item);
		_redoStack.clear();
	}

	void undo(scope Item delegate(Item) applyUndo)
	{
		undoRedoImpl(_undoStack, _redoStack, applyUndo);
	}

	void redo(scope Item delegate(Item) applyUndo)
	{
		undoRedoImpl(_redoStack, _undoStack, applyUndo);
	}

	void clear()
	{
		_undoStack.clear();
		_redoStack.clear();
	}

	@property size_t undoSize() { return _undoStack.length; }
	@property size_t redoSize() { return _redoStack.length; }

	private void undoRedoImpl(
		ref ChunkedBuffer!Item fromStack,
		ref ChunkedBuffer!Item toStack,
		scope Item delegate(Item) applyUndo)
	{
		if (fromStack.length == 0) return;

		bool group = fromStack.back.group;

		while (!fromStack.empty && fromStack.back.group == group)
		{
			// Get item to restore
			Item undoItem = fromStack.back;
			fromStack.removeBack();

			// Restore state
			Item redoItem = applyUndo(undoItem);

			// Save current state
			toStack.putBack(redoItem);
		}

		if (!_undoStack.empty)
			_currentGroup = _undoStack.back.group;
	}
}

// Test undo/redo.
unittest
{
	import textedit.textbuffer;
	PieceTable table = PieceTable("abcdef");
	static struct UndoItem
	{
		PieceRestoreRange pieceUndo;
		// Piece ranges in one group have the same flag
		bool group;
	}
	UndoStack!UndoItem undoStack;

	UndoItem onUndoRedoAction(UndoItem undoItem)
	{
		auto pieceUndo = undoItem.pieceUndo.apply(table.pieces.length);
		return UndoItem(pieceUndo, undoItem.group);
	}

	void getUndo(PieceRestoreRange pieceUndo)
	{
		undoStack.commitUndoItem(UndoItem(pieceUndo));
	}

	//table[].writeln;
	//table.pieces.writeln;

	assert(undoStack.undoSize == 0);

	getUndo(table.remove(2, 2));
	assert(table[].equalDchars("abef"));
	//table[].writeln;
	//table.pieces.writeln;

	assert(undoStack.undoSize == 1);

	undoStack.undo(&onUndoRedoAction);
	assert(table[].equalDchars("abcdef"));
	//table[].writeln;
	//table.pieces.writeln;

	assert(undoStack.undoSize == 0);
	assert(undoStack.redoSize == 1);

	undoStack.redo(&onUndoRedoAction);
	//table[].writeln;
	//table.pieces.writeln;
	assert(table[].equalDchars("abef"));


	table = PieceTable("abcdef");
	undoStack.clear;
	//table[].writeln;

	getUndo(table.insert(2, "qw"));
	assert(undoStack.undoSize == 1);

	undoStack.undo(&onUndoRedoAction);
	assert(table[].equalDchars("abcdef"));
	undoStack.redo(&onUndoRedoAction);
	assert(table[].equalDchars("abqwcdef"));


	// Test undo/redo grouping.
	table = PieceTable("абвгде");
	undoStack.clear;

	undoStack.beginGroup();
	getUndo(table.insert(4, "12"));
	getUndo(table.remove(6, 4));
	undoStack.endGroup();
	assert(table[].equalDchars("аб12де"));

	undoStack.beginGroup();
	getUndo(table.insert(4, "12"));
	getUndo(table.remove(4, 2));
	undoStack.endGroup();
	assert(table[].equalDchars("аб12де"));

	getUndo(table.remove(4, 2));
	assert(table[].equalDchars("абде"));

	undoStack.beginGroup();
	getUndo(table.insert(4, "12"));
	undoStack.endGroup();
	assert(table[].equalDchars("аб12де"));

	undoStack.undo(&onUndoRedoAction);
	assert(table[].equalDchars("абде"));

	undoStack.undo(&onUndoRedoAction);
	assert(table[].equalDchars("аб12де"));

	undoStack.undo(&onUndoRedoAction);
	assert(table[].equalDchars("аб12де"));

	undoStack.undo(&onUndoRedoAction);
	assert(table[].equalDchars("абвгде"));


	// Test redo discarding
	table = PieceTable("абвгде");
	undoStack.clear();

	undoStack.beginGroup();
	getUndo(table.insert(0, "a"));
	getUndo(table.insert(0, "a"));
	getUndo(table.insert(0, "a"));
	getUndo(table.insert(0, "a"));
	undoStack.endGroup();

	undoStack.undo(&onUndoRedoAction);
	assert(undoStack._redoStack.length == 4);

	getUndo(table.insert(0, "a"));
	assert(undoStack._redoStack.length == 0);
}
