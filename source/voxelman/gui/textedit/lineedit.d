/**
Copyright: Copyright (c) 2017-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.gui.textedit.lineedit;

import core.time : MonoTime;
import std.format : formattedWrite;
import voxelman.container.gapbuffer;
import voxelman.log;
import voxelman.gui;
import voxelman.math;
import voxelman.graphics;
import voxelman.container.chunkedbuffer;
import voxelman.gui.textedit.cursor;
import voxelman.gui.textedit.textmodel;
import voxelman.gui.textedit.linebuffer;
import voxelman.gui.textedit.texteditor;
import voxelman.gui.textedit.texteditorview;

@Component("gui.LineEditData", Replication.none)
struct LineEditData
{
	TextViewSettings settings;
	void delegate(string) enterHandler;

	GapBuffer!char textData;
	Selection selection;
	MonoTime blinkStart;
}

struct LineEditLogic
{
	LineEditData* data;
	GuiContext ctx;

	alias data this;

	void resetBlinkTimer()
	{
		blinkStart = MonoTime.currTime;
	}

	void moveSelectionCursor(MoveCommand com, bool extendSelection)
	{
		selection.end = moveCursor(selection.end, com);
		if (!extendSelection) selection.start = selection.end;
	}

	void copySelection()
	{
		auto sel = getSelectionForCopyCut();
		copyText(sel.start.byteOffset, sel.end.byteOffset);
	}

	void copyText(size_t from, size_t to)
	{
		auto copiedText = textData[from..to].toChunkedRange.byItem;
		ctx.clipboard = copiedText;
	}

	size_t length() { return textData.length; }
	alias opDollar = length;

	ChunkedRange!char opSlice(size_t from, size_t to)
	{
		return textData[from..to].toChunkedRange;
	}

	Selection getSelectionForCopyCut()
	{
		return selection.normalized;
	}

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

		//auto pieceUndo =
		textData.putAt(cur.byteOffset, str);
		//int insertedLines = lines.onPaste(cur, str);
		auto afterInsertedText = Cursor(cur.byteOffset + str.length, cur.line);
		//auto undoItem = UndoItem(pieceUndo, cur, afterInsertedText, UndoCommand.undoInsert, selection);
		//putUndo(undoItem);
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
		assert(from.byteOffset < to.byteOffset, "from.byteOffset < to.byteOffset");
		//auto pieceUndo =
		infof("remove %s %s", from.byteOffset, to.byteOffset-from.byteOffset);
		textData.remove(from.byteOffset, to.byteOffset-from.byteOffset);
		//auto undoItem = UndoItem(pieceUndo, from, to, UndoCommand.undoRemove, selection);
		//putUndo(undoItem);
		//lines.onRemove(from, to);
	}

	void onCommand(EditorCommand com)
	{
		switch(com.type)
		{
			case EditorCommandType.insert_eol:
				if (enterHandler) enterHandler(cast(string)textData.getContinuousSlice(0, textData.length));
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
			case EditorCommandType.delete_right_char:
				if (selection.empty)
				{
					auto rightCur = moveCursor(selection.end, MoveCommand.move_right_char);
					removeAndUpdateSelection(Selection(selection.end, rightCur));
				}
				else removeAndUpdateSelection(selection);
				break;
			case EditorCommandType.delete_right_word: break;
			case EditorCommandType.delete_right_line: break;
			case EditorCommandType.cut: cutSelection(); break;
			case EditorCommandType.copy: copySelection(); break;
			case EditorCommandType.paste: replaceSelection(ctx.clipboard); break;
			case EditorCommandType.select_all:
				selection = Selection(Cursor(0,0), Cursor(length, 0));
				break;
			case EditorCommandType.undo:
				//undo();
				break;
			case EditorCommandType.redo:
				//redo();
				break;
			case EditorCommandType.cur_move_first: .. case EditorCommandType.cur_move_last:
				selection.end = moveCursor(selection.end, com.toMoveCommand);
				if (!com.extendSelection) selection.start = selection.end;
				break;
			default: break;
		}
	}
	import std.utf : stride, strideBack;

	uint strideAt(size_t offset)
	{
		auto str = textData[offset..$];
		return stride(str);
	}

	size_t nextOffset(size_t offset)
	{
		return offset + strideAt(offset);
	}

	size_t prevOffset(size_t offset)
	{
		return offset - strideBack(textData[0u..offset]);
	}

	Cursor moveCursor(Cursor cur, MoveCommand com)
	{
		switch(com) with(MoveCommand) {
			case move_right_char:
				if (cur.byteOffset < textData.length) {
					auto newOffset = nextOffset(cur.byteOffset);
					cur.byteOffset = newOffset;
				}
				break;
			case move_left_char:
				if (cur.byteOffset > 0) {
					auto newOffset = prevOffset(cur.byteOffset);
					cur.byteOffset = newOffset;
				}
				break;
			case move_to_bol: cur.byteOffset = 0; break;
			case move_to_eol: cur.byteOffset = textData.length; break;
			default: break;
		}
		return cur;
	}

	void clear()
	{
		textData.clear();
		selection = Selection();
	}

	Cursor calcCursorPos(ivec2 absPointerPos, ivec2 absPos)
	{
		ivec2 viewportPointerPos = absPointerPos - absPos;
		return calcCursorPos(viewportPointerPos);
	}

	Cursor calcCursorPos(ivec2 canvasPointerPos)
	{
		//if (data.editor.textData.length == 0) return Cursor();
		ivec2 glyphSize = settings.scaledGlyphSize;

		auto range = glyphWidthRange(&settings, textData[]);
		foreach(int x, int width; range)
		{
			int glyphCenter = x + width/2;
			if (canvasPointerPos.x < glyphCenter) break;
		}
		auto cursorBytes = range.byteOffset;
		return Cursor(cursorBytes);
	}
}

struct LineEdit
{
	static:

	enum vmargin = 2;

	WidgetProxy create(WidgetProxy parent, void delegate(string) enterHandler = null)
	{
		TextViewSettings settings;
		settings.font = parent.ctx.style.font;
		settings.color = parent.ctx.style.color;
		return parent.createChild(
			LineEditData(settings, enterHandler),
			WidgetEvents(
				&enterWidget, &drawWidget,
				&pointerPressed, &pointerReleased, &pointerMoved,
				&keyPressed, &charTyped),
			WidgetIsFocusable()
		).minSize(0, settings.font.metrics.height + vmargin*2);
	}

	void enterWidget(WidgetProxy widget, ref PointerEnterEvent event)
	{
		widget.ctx.cursorIcon = CursorIcon.ibeam;
	}

	void drawWidget(WidgetProxy widget, ref DrawEvent event)
	{
		if (event.bubbling) return;

		auto transform = widget.getOrCreate!WidgetTransform;
		auto data = widget.get!LineEditData;
		Selection sel = data.selection;
		ivec2 glyphSize = data.settings.scaledGlyphSize;

		ivec2 textPos = transform.absPos + ivec2(0, vmargin);

		auto mesherParams = event.renderQueue.defaultText();
		mesherParams.scissors = irect(transform.absPos, transform.size);
		mesherParams.color = data.settings.color;
		mesherParams.scale = data.settings.fontScale;
		mesherParams.font = cast(FontRef)data.settings.font;
		mesherParams.depth = event.depth+1;
		mesherParams.origin = textPos;
		mesherParams.monospaced = data.settings.monospaced;

		mesherParams.meshText(data.textData[]);

		// draw selection
		{
			Selection normSel = sel.normalized;
			enum selCol = Color4ub(180, 230, 255, 128);
			int selStartX = textWidth(&data.settings, data.textData[0..normSel.start.byteOffset]);
			int selEndX = textWidth(&data.settings, data.textData[0..normSel.end.byteOffset]);
			vec2 size = vec2(selEndX - selStartX, glyphSize.y);
			vec2 pos = vec2(textPos) + vec2(selStartX, 0);
			event.renderQueue.drawRectFill(pos, size, event.depth, selCol);
		}

		// draw cursor
		if (widget.ctx.focusedWidget == widget)
		{
			auto sinceBlinkStart = MonoTime.currTime - data.blinkStart;
			if (sinceBlinkStart.total!"msecs" % 1000 < 500)
			{
				int cursorX = textWidth(&data.settings, data.textData[0..sel.end.byteOffset]);
				vec2 pos = vec2(textPos) + vec2(cursorX, 0);
				vec2 size = vec2(1, glyphSize.y);
				event.renderQueue.drawRectFill(pos, size, event.depth+1, data.settings.color);
			}
		}

		event.depth += 2;
	}

	void keyPressed(WidgetProxy widget, ref KeyPressEvent event)
	{
		auto data = widget.get!LineEditData;
		auto logic = LineEditLogic(data, widget.ctx);

		logic.resetBlinkTimer();

		auto command = keyPressToCommand(event);
		logic.onCommand(command);
	}

	void charTyped(WidgetProxy widget, ref CharEnterEvent event)
	{
		import std.utf : encode;
		import std.typecons : Yes;
		auto data = widget.get!LineEditData;
		auto logic = LineEditLogic(data, widget.ctx);
		char[4] buf;
		auto numBytes = encode!(Yes.useReplacementDchar)(buf, event.character);
		logic.replaceSelection(buf[0..numBytes]);
		logic.resetBlinkTimer();
	}

	void clear(WidgetProxy widget)
	{
		auto data = widget.get!LineEditData;
		auto logic = LineEditLogic(data, widget.ctx);
		logic.clear;
	}

	void pointerPressed(WidgetProxy widget, ref PointerPressEvent event)
	{
		if (event.button == PointerButton.PB_LEFT)
		{
			auto transform = widget.getOrCreate!WidgetTransform;
			auto data = widget.get!LineEditData;
			auto logic = LineEditLogic(data, widget.ctx);
			Cursor cursorPos = logic.calcCursorPos(event.pointerPosition, transform.absPos);

			data.selection.end = cursorPos;

			bool extendSelection = event.shift;
			if (!extendSelection)
				data.selection.start = cursorPos;
		}
		event.handled = true;
	}

	void pointerReleased(WidgetProxy widget, ref PointerReleaseEvent event)
	{
		event.handled = true;
	}

	void setEnterHandler(WidgetProxy widget, void delegate(string) enterHandler)
	{
		auto data = widget.get!LineEditData;
		data.enterHandler = enterHandler;
	}

	void pointerMoved(WidgetProxy widget, ref PointerMoveEvent event)
	{
		if (widget.ctx.state.pressedWidget == widget)
		{
			auto transform = widget.getOrCreate!WidgetTransform;
			auto data = widget.get!LineEditData;
			auto logic = LineEditLogic(data, widget.ctx);
			data.selection.end = logic.calcCursorPos(event.newPointerPos, transform.absPos);
		}
		event.handled = true;
	}
}
