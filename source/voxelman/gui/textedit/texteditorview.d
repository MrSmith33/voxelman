/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.gui.textedit.texteditorview;

import std.datetime : MonoTime;
import std.stdio : writefln, writeln;
import std.array;

import datadriven.entityman : EntityManager;
import voxelman.container.buffer;
import voxelman.graphics;
import voxelman.log;
import voxelman.gui;
import voxelman.math;
import voxelman.platform;
import voxelman.text.linebuffer;
import voxelman.text.scale;

import voxelman.gui.textedit.texteditor;
import voxelman.gui.textedit.cursor;
import voxelman.gui.textedit.linebuffer;
import voxelman.gui.textedit.textmodel;

void registerComponents(ref EntityManager widgets)
{
	widgets.registerComponent!TextEditorViewportData;
	widgets.registerComponent!TextEditorLineNumbersData;
}

@Component("gui.TextEditorViewportData", Replication.none)
struct TextEditorViewportData
{
	TextModel editor;
	TextViewSettingsRef settings;
	MonoTime blinkStart;

	ivec2 textPos; // on text canvas, in pixels

	int autoscrollY;
	int firstVisibleLine;
	int lastVisibleLine;
	bool autoscroll;
	// If true prevents scrolling up
	// If false, scrolling up will disable autoscroll
	bool hardAutoscroll;

	void resetBlinkTimer()
	{
		blinkStart = MonoTime.currTime;
	}

	void scroll(ivec2 delta)
	{
		if (autoscroll && hardAutoscroll) return;

		textPos += ivec2(0, delta.y * settings.scrollSpeedLines * settings.scaledGlyphH);
		if (textPos.y < autoscrollY)
		{
			autoscroll = false;
		}
	}

	void update(GuiContext ctx, ivec2 size)
	{
		ivec2 textSizeInGlyphs = ivec2(0, editor.numLines);
		ivec2 textSizeInPixels = textSizeInGlyphs * settings.scaledGlyphSize;

		int maxVisibleLines = divCeil(size.y, settings.scaledGlyphH);
		autoscrollY = (editor.numLines - maxVisibleLines) * settings.scaledGlyphH;
		autoscrollY = clamp(autoscrollY, 0, textSizeInPixels.y);
		if (autoscroll)
		{
			textPos.y = autoscrollY;
		}

		textPos = vector_clamp(textPos, ivec2(0, 0), textSizeInPixels);

		//if (editor.textSizeInGlyphs.y == 0) return;

		firstVisibleLine = clamp(textPos.y / settings.scaledGlyphH, 0, editor.lastLine);

		int viewportEndPos = textPos.y + size.y;
		lastVisibleLine = clamp(viewportEndPos / settings.scaledGlyphH, 0, editor.lastLine);

		ctx.debugText.putfln("textPos %s", textPos);
		ctx.debugText.putfln("size %s", size);
		ctx.debugText.putfln("viewportEndPos %s", viewportEndPos);
		ctx.debugText.putfln("firstVisibleLine %s", firstVisibleLine);
		ctx.debugText.putfln("lastVisibleLine %s", lastVisibleLine);
	}
}

struct TextEditorViewportLogic
{
	static:
	WidgetProxy create(
		WidgetProxy parent,
		TextModel editor,
		TextViewSettingsRef settings)
	{
		return parent.createChild(
			TextEditorViewportData(editor, settings, MonoTime.currTime),
			WidgetEvents(
				&onScroll, &enterWidget, &drawWidget,
				&pointerPressed, &pointerReleased, &pointerMoved,
				&keyPressed, &charTyped
				),
			WidgetIsFocusable()
		);
	}

	void onScroll(WidgetProxy widget, ref ScrollEvent event)
	{
		auto data = widget.get!TextEditorViewportData;
		data.scroll(ivec2(event.delta));
	}

	void enterWidget(WidgetProxy widget, ref PointerEnterEvent event)
	{
		widget.ctx.cursorIcon = CursorIcon.ibeam;
	}

	void drawWidget(WidgetProxy widget, ref DrawEvent event)
	{
		if (event.bubbling) return;

		auto transform = widget.getOrCreate!WidgetTransform;
		auto data = widget.get!TextEditorViewportData;
		auto editor = data.editor;
		auto settings = data.settings;
		data.update(widget.ctx, transform.size);
		Selection sel = data.editor.selection;

		auto from = editor.lineInfo(data.firstVisibleLine).startOffset;
		auto to = editor.lineInfo(data.lastVisibleLine).endOffset;
		auto renderedText = editor[from..to].byItem;

		MonoTime startTime = MonoTime.currTime;

		auto mesherParams = event.renderQueue.defaultText();
		mesherParams.scissors = irect(transform.absPos, transform.size);
		mesherParams.scale = settings.fontScale;
		mesherParams.color = settings.color;
		mesherParams.font = cast(FontRef)settings.font;
		mesherParams.depth = event.depth+1;
		mesherParams.origin = transform.absPos;
		mesherParams.monospaced = settings.monospaced;

		mesherParams.meshText(renderedText);

		ivec2 glyphSize = settings.scaledGlyphSize;

		// draw selection
		{
			enum selCol = rgb(180, 230, 255);

			Selection normSel = sel.normalized;
			int firstSelectedLine = normSel.start.line;
			int lastSelectedLine = normSel.end.line;
			int firstVisibleSelectedLine = max(firstSelectedLine, data.firstVisibleLine);
			int lastVisibleSelectedLine = min(lastSelectedLine, data.lastVisibleLine);

			foreach(line; firstVisibleSelectedLine..lastVisibleSelectedLine+1)
			{
				ulong lineStart = 0;
				ulong lineEnd;

				auto lineInfo = editor.lineInfo(line);

				if (line == firstSelectedLine) lineStart = normSel.start.byteOffset;
				else lineStart = lineInfo.startOffset;

				if (line == lastSelectedLine) lineEnd = normSel.end.byteOffset;
				else lineEnd = lineInfo.endOffset;

				int viewportTopOffset = line - data.firstVisibleLine;


				int selStartX = textWidth(settings, editor[lineInfo.startOffset..lineStart].byItem);
				int selEndX = textWidth(settings, editor[lineInfo.startOffset..lineEnd].byItem);

				if (line != lastSelectedLine) selEndX += glyphSize.x; // make newline visible

				vec2 size = vec2(selEndX - selStartX, glyphSize.y);
				vec2 pos = vec2(transform.absPos) + vec2(selStartX, viewportTopOffset*glyphSize.y);

				event.renderQueue.drawRectFill(pos, size, event.depth, selCol);
			}
		}

		// draw cursor
		if (widget.ctx.focusedWidget == widget)
		{
			auto sinceBlinkStart = MonoTime.currTime - data.blinkStart;
			if (sinceBlinkStart.total!"msecs" % 1000 < 500)
			{
				int viewportTopOffset = sel.end.line - data.firstVisibleLine;
				auto lineInfo = editor.lineInfo(sel.end.line);
				int cursorX = textWidth(settings, editor[lineInfo.startOffset..sel.end.byteOffset].byItem);
				vec2 pos = vec2(transform.absPos) + vec2(cursorX, viewportTopOffset*glyphSize.y);
				vec2 size = vec2(1, glyphSize.y);
				event.renderQueue.drawRectFill(pos, size, event.depth+1, rgb(0,0,0));
			}
		}

		event.depth += 2;

		widget.ctx.debugText.putfln("Append glyphs: %sus", (MonoTime.currTime - startTime).total!"usecs");
		widget.ctx.debugText.putfln("Lines: %s", editor.numLines);
		//widget.ctx.debugText.putfln("Size: %s", data.editor.textSizeInGlyphs);
		widget.ctx.debugText.putfln("sel start: %s", sel.start);
		widget.ctx.debugText.putfln("sel end: %s", sel.end);
	}

	void keyPressed(WidgetProxy widget, ref KeyPressEvent event)
	{
		auto data = widget.get!TextEditorViewportData;
		data.resetBlinkTimer();
		auto command = keyPressToCommand(event);
		data.editor.onCommand(command);

		if (event.keyCode == KeyCode.KEY_M && event.control)
			data.settings.monospaced = !data.settings.monospaced;
	}

	void charTyped(WidgetProxy widget, ref CharEnterEvent event)
	{
		import std.utf : encode, Yes;
		auto data = widget.get!TextEditorViewportData;
		char[4] buf;
		auto numBytes = encode!(Yes.useReplacementDchar)(buf, event.character);
		data.editor.onCommand(EditorCommand(EditorCommandType.input, 0, buf[0..numBytes]));
		//data.editor.replaceSelection(buf[0..numBytes]);
		data.resetBlinkTimer();
	}

	void pointerPressed(WidgetProxy widget, ref PointerPressEvent event)
	{
		if (event.button == PointerButton.PB_LEFT)
		{
			auto transform = widget.getOrCreate!WidgetTransform;
			auto data = widget.get!TextEditorViewportData;

			Cursor cursorPos = calcCursorPos(event.pointerPosition, transform.absPos, data);

			data.editor.selection.end = cursorPos;

			bool extendSelection = event.shift;
			if (!extendSelection)
				data.editor.selection.start = cursorPos;
		}
		event.handled = true;
	}

	void pointerReleased(WidgetProxy widget, ref PointerReleaseEvent event)
	{
		event.handled = true;
	}

	void pointerMoved(WidgetProxy widget, ref PointerMoveEvent event)
	{
		if (widget.ctx.state.pressedWidget == widget)
		{
			auto transform = widget.getOrCreate!WidgetTransform;
			auto data = widget.get!TextEditorViewportData;
			data.editor.selection.end = calcCursorPos(event.newPointerPos, transform.absPos, data);
		}
		event.handled = true;
	}

	Cursor calcCursorPos(ivec2 absPointerPos, ivec2 absPos, TextEditorViewportData* data)
	{
		ivec2 viewportPointerPos = absPointerPos - absPos;
		ivec2 canvasPointerPos = viewportPointerPos + data.textPos;
		return calcCursorPos(canvasPointerPos, data);
	}

	Cursor calcCursorPos(ivec2 canvasPointerPos, TextEditorViewportData* data)
	{
		//if (data.editor.textData.length == 0) return Cursor();
		ivec2 glyphSize = data.settings.scaledGlyphSize;

		int cursorLine = clamp(canvasPointerPos.y / glyphSize.y, 0, data.editor.lastLine);

		auto lineInfo = data.editor.lineInfo(cursorLine);
		auto from = lineInfo.startOffset;
		auto to = lineInfo.endOffset;
		auto text = data.editor[from..to].byItem; // text without newline

		auto range = glyphWidthRange(data.settings, text);
		foreach(int x, int width; range)
		{
			int glyphCenter = x + width/2;
			if (canvasPointerPos.x < glyphCenter) break;
		}
		auto cursorBytes = lineInfo.startOffset + range.byteOffset;
		return Cursor(cursorBytes, cursorLine);
	}
}

int textWidth(T)(TextViewSettingsRef settings, T text)
{
	auto range = glyphWidthRange(settings, text);
	foreach(b, c; range) {}
	return range.x;
}


auto glyphWidthRange(R)(TextViewSettingsRef settings, R text)
{
	return GlyphWidthRange!R(settings, text);
}

struct GlyphWidthRange(R)
{
	import std.utf : decodeFront, Yes;
	TextViewSettingsRef settings;
	R input;
	int x;
	size_t byteOffset;

	int opApply(scope int delegate(int x, int width) del)
	{
		int glyphW = settings.scaledGlyphW;
		x = 0;
		byteOffset = 0;

		auto initialBytes = input.length;
		if (settings.monospaced)
		{
			int column;

			while(!input.empty)
			{
				dchar codePoint = decodeFront!(Yes.useReplacementDchar)(input);
				int width;
				if (codePoint == '\t')
				{
					int tabGlyphs = tabWidth(settings.tabSize, column);
					width = tabGlyphs * glyphW;
					column += tabGlyphs;
				}
				else
				{
					width = glyphW;
					++column;
				}

				if (auto ret = del(x, width)) return ret;

				byteOffset = initialBytes - input.length;
				x += width;
			}
		}
		else
		{
			while(!input.empty)
			{
				dchar codePoint = decodeFront!(Yes.useReplacementDchar)(input);
				int width;
				if (codePoint == '\t')
				{
					int tabPixels = tabWidth(settings.tabSize * glyphW, x);
					width = tabPixels;
				}
				else
				{
					const Glyph* glyph = settings.font.getGlyph(codePoint);
					width = glyph.metrics.advanceX;
				}

				if (auto ret = del(x, width)) return ret;

				byteOffset = initialBytes - input.length;
				x += width;
			}
		}
		byteOffset = initialBytes - input.length;
		return 0;
	}
}

EditorCommand keyPressToCommand(ref KeyPressEvent event)
{
	alias ComType = EditorCommandType;

	EditorCommand moveCommand(MoveCommand com, bool extendSelection)
	{
		return EditorCommand(cast(EditorCommandType)(com + EditorCommandType.cur_move_first), extendSelection);
	}

	switch(event.keyCode) with(KeyCode)
	{
	case KEY_LEFT:  return moveCommand(MoveCommand.move_left_char, event.shift);
	case KEY_RIGHT: return moveCommand(MoveCommand.move_right_char, event.shift);
	case KEY_UP:    return moveCommand(MoveCommand.move_up_line, event.shift);
	case KEY_DOWN:  return moveCommand(MoveCommand.move_down_line, event.shift);
	case KEY_HOME:  return moveCommand(MoveCommand.move_to_bol, event.shift);
	case KEY_END:   return moveCommand(MoveCommand.move_to_eol, event.shift);
	case KEY_TAB:   return EditorCommand(ComType.insert_tab);
	case KEY_ENTER: case KEY_KP_ENTER: return EditorCommand(ComType.insert_eol);
	case KEY_BACKSPACE:
		if (event.control)
		{
			if (event.shift) return EditorCommand(ComType.delete_left_line);
			else return EditorCommand(ComType.delete_left_word);
		}
		else return EditorCommand(ComType.delete_left_char);
	case KEY_DELETE:
		if (event.control)
		{
			if (event.shift) return EditorCommand(ComType.delete_right_line);
			else return EditorCommand(ComType.delete_right_word);
		}
		else return EditorCommand(ComType.delete_right_char);
	case KEY_A: if (event.control) return EditorCommand(ComType.select_all); break;
	case KEY_C: if (event.control) return EditorCommand(ComType.copy); break;
	case KEY_X: if (event.control) return EditorCommand(ComType.cut); break;
	case KEY_V: if (event.control) return EditorCommand(ComType.paste); break;
	case KEY_Z:
		if (event.control)
		{
			if (event.shift) return EditorCommand(ComType.redo);
			else return EditorCommand(ComType.undo);
		}
		break;
	default: break;
	}
	return EditorCommand(ComType.none);
}

@Component("gui.TextEditorLineNumbersData", Replication.none)
struct TextEditorLineNumbersData
{
	// component connections
	TextModel editor;
	TextViewSettingsRef settings;
	WidgetId viewport;

	// vars
	enum leftSpacing = 1;
	enum rightSpacing = 2;

	int widthInGlyphs()
	{
		return numDigitsInNumber(editor.numLines) + leftSpacing + rightSpacing;
	}

	int widthInPixels(int _widthInGlyphs)
	{
		return cast(int)(_widthInGlyphs * settings.scaledGlyphW);
	}
}

struct TextEditorLineNumbersLogic
{
	static:
	WidgetProxy create(
		WidgetProxy parent,
		TextModel editor,
		TextViewSettingsRef settings)
	{
		return parent.createChild(
			TextEditorLineNumbersData(editor, settings),
			WidgetEvents(&drawWidget, &measure));
	}

	void setViewport(WidgetProxy widget, WidgetProxy viewport)
	{
		auto data = widget.get!TextEditorLineNumbersData;
		data.viewport = viewport;
	}

	void drawWidget(WidgetProxy widget, ref DrawEvent event)
	{
		if (event.bubbling) return;

		auto transform = widget.getOrCreate!WidgetTransform;
		auto data = widget.get!TextEditorLineNumbersData;
		auto viewportData = widget.ctx.get!TextEditorViewportData(data.viewport);

		int widthInGlyphs = data.widthInGlyphs;

		auto mesherParams = event.renderQueue.defaultText();
		mesherParams.scale = data.settings.fontScale;
		mesherParams.origin = transform.absPos;
		mesherParams.monospaced = true;

		foreach (line; viewportData.firstVisibleLine..viewportData.lastVisibleLine+1)
		{
			size_t lineNumber = line+1;
			size_t digits = numDigitsInNumber(lineNumber);
			size_t spacing = widthInGlyphs - (digits + data.rightSpacing);
			foreach (_; 0..spacing)
				mesherParams.meshText(" ");
			mesherParams.meshTextf("%s\n", lineNumber);
		}

		widget.ctx.debugText.putfln("Line num w: %s", widthInGlyphs);
	}

	void measure(WidgetProxy widget, ref MeasureEvent event)
	{
		auto transform = widget.getOrCreate!WidgetTransform;
		auto data = widget.get!TextEditorLineNumbersData;
		int widthInGlyphs = data.widthInGlyphs;
		int widthInPixels = data.widthInPixels(widthInGlyphs);
		transform.measuredSize = ivec2(widthInPixels, 0);
	}
}
/*
struct TextEditorMinimap
{
	// component connections
	TextEditorCRef document;
	TextViewSettingsRef settings;
	TextEditorViewportConstRef viewport;

	enum glyphSize = ivec2(1, 2);

	// vars
	ivec2 position;
	ivec2 size;

	int glyphsX;

	// private
	private Bitmap image;

	void update(ref LineBuffer debugText)
	{

	}

	void render(RenderQueue renderQueue, ref LineBuffer debugText)
	{
		//lvec2 textSizeInPixels = document.textSizeInGlyphs * settings.scaledGlyphSize;
		//long scrollPercent = viewport.textPos.y / textSizeInPixels.y;

		//long minimapAreaWidth = viewport.size.x / settings.scaledGlyphW;

		//vec2 minimapPos = position + vec2(viewport.size.x - minimapAreaWidth, 0);
		//vec2 size = vec2(minimapAreaWidth, viewport.size.y);
		renderQueue.drawRectFill(vec2(position), vec2(size), 0, Color4ub(200, 200, 200, 255));
	}
}
*/
