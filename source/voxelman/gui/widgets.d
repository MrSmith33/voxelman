/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.gui.widgets;

import std.stdio;
import voxelman.gui;
import voxelman.math;
import voxelman.graphics;

void registerComponents(GuiContext ctx)
{
	ctx.widgets.registerComponent!TextButtonData;
	ctx.widgets.registerComponent!LinearLayoutSettings;
	ctx.widgets.registerComponent!hexpand;
	ctx.widgets.registerComponent!vexpand;
	ctx.widgets.registerComponent!ListData;
}


enum baseColor = rgb(26, 188, 156);
enum hoverColor = rgb(22, 160, 133);
enum color_clouds = rgb(236, 240, 241);
enum color_silver = rgb(189, 195, 199);
enum color_concrete = rgb(149, 165, 166);
enum color_asbestos = rgb(127, 140, 141);
enum color_white = rgb(250, 250, 250);

enum color_wet_asphalt = rgb(52, 73, 94);

struct PanelLogic
{
	static:
	WidgetId create(GuiContext ctx, WidgetId parent, ivec2 pos, ivec2 size, Color4ub color)
	{
		WidgetId panel = ctx.createWidget(
			parent,
			WidgetEvents(&drawWidget),
			WidgetTransform(pos, size),
			WidgetStyle(color));
		return panel;
	}

	void drawWidget(WidgetId wid, ref DrawEvent event)
	{
		if (event.sinking)
		{
			auto transform = event.ctx.getOrCreate!WidgetTransform(wid);
			auto style = event.ctx.get!WidgetStyle(wid);
			event.renderQueue.drawRectFill(vec2(transform.absPos), vec2(transform.size), event.depth, style.color);
			vec2 linePos = vec2(transform.absPos.x+transform.size.x-1, 0);
			event.renderQueue.drawRectFill(linePos, vec2(1, transform.size.y), event.depth, color_concrete);
			event.depth += 1;
			event.renderQueue.pushClipRect(irect(transform.absPos, transform.size));
		}
		else
		{
			event.renderQueue.popClipRect();
		}
	}
}


alias ClickHandler = void delegate();

@Component("gui.TextButtonData", Replication.none)
struct TextButtonData
{
	string text;
	FontRef font;
	ClickHandler handler;
	uint data;
}

enum BUTTON_PRESSED = 0b0001;
enum BUTTON_HOVERED = 0b0010;
enum BUTTON_SELECTED = 0b0100;

enum buttonNormalColor = rgb(255, 255, 255);
enum buttonHoveredColor = rgb(241, 241, 241);
enum buttonPressedColor = rgb(229, 229, 229);
Color4ub[4] buttonColors = [buttonNormalColor, buttonNormalColor, buttonHoveredColor, buttonPressedColor];

struct TextButtonLogic
{
	static:
	WidgetId create(GuiContext ctx, WidgetId parent, string text, FontRef font, ClickHandler handler)
	{
		WidgetId button = ctx.createWidget(parent,
			TextButtonData(text, font, handler),
			hexpand(),
			WidgetEvents(
				&drawWidget, &pointerMoved, &pointerPressed, &pointerReleased,
				&enterWidget, &leaveWidget, &clickWidget, &measure),
			WidgetTransform(ivec2(), ivec2(), ivec2(0, font.metrics.height)),
			WidgetStyle(baseColor),
			WidgetRespondsToPointer());
		return button;
	}

	void drawWidget(WidgetId wid, ref DrawEvent event)
	{
		if (event.sinking)
		{
			auto data = event.ctx.get!TextButtonData(wid);
			auto transform = event.ctx.getOrCreate!WidgetTransform(wid);
			auto style = event.ctx.get!WidgetStyle(wid);

			auto params = event.renderQueue.startTextAt(vec2(transform.absPos) + vec2(transform.size/2));
			params.font = data.font;
			params.monospaced = true;
			params.depth = event.depth+1;
			params.color = color_wet_asphalt;
			params.meshTextAligned(data.text, Alignment.center, Alignment.center);

			event.renderQueue.drawRectFill(vec2(transform.absPos), vec2(transform.size), event.depth, buttonColors[data.data]);
			event.depth += 2;
		}
	}

	void pointerMoved(WidgetId wid, ref PointerMoveEvent event) { event.handled = true; }

	void pointerPressed(WidgetId wid, ref PointerPressEvent event)
	{
		event.ctx.get!TextButtonData(wid).data |= BUTTON_PRESSED;
		event.handled = true;
	}

	void pointerReleased(WidgetId wid, ref PointerReleaseEvent event)
	{
		event.ctx.get!TextButtonData(wid).data &= ~BUTTON_PRESSED;
		event.handled = true;
	}

	void enterWidget(WidgetId wid, ref PointerEnterEvent event)
	{
		event.ctx.get!TextButtonData(wid).data |= BUTTON_HOVERED;
	}

	void leaveWidget(WidgetId wid, ref PointerLeaveEvent event)
	{
		event.ctx.get!TextButtonData(wid).data &= ~BUTTON_HOVERED;
	}

	void clickWidget(WidgetId wid, ref PointerClickEvent event)
	{
		auto data = event.ctx.get!TextButtonData(wid);
		if (data.handler) data.handler();
	}

	void measure(WidgetId wid, ref MeasureEvent event)
	{
		auto transform = event.ctx.getOrCreate!WidgetTransform(wid);
		auto data = event.ctx.get!TextButtonData(wid);
		TextMesherParams params;
		params.font = data.font;
		params.monospaced = true;
		measureText(params, data.text);
		transform.measuredSize = ivec2(params.size)+ivec2(2,2);
	}
}


@Component("gui.vexpand", Replication.none)
struct vexpand{}

@Component("gui.hexpand", Replication.none)
struct hexpand{}

@Component("gui.LinearLayoutSettings", Replication.none)
struct LinearLayoutSettings
{
	int spacing; /// distance between items
	int padding; /// borders around items

	// internal state
	int numExpandableChildren;
}

alias HLine = Line!true;
alias VLine = Line!false;

struct Line(bool horizontal)
{
	static:
	static if (horizontal) {
		WidgetId create(GuiContext ctx, WidgetId parent) {
			return ctx.createWidget(parent, hexpand(), WidgetEvents(&drawWidget, &measure));
		}
		void measure(WidgetId wid, ref MeasureEvent event) {
			auto transform = event.ctx.getOrCreate!WidgetTransform(wid);
			transform.measuredSize = ivec2(0,1);
		}
	} else {
		WidgetId create(GuiContext ctx, WidgetId parent) {
			return ctx.createWidget(parent, vexpand(), WidgetEvents(&drawWidget, &measure));
		}
		void measure(WidgetId wid, ref MeasureEvent event) {
			auto transform = event.ctx.getOrCreate!WidgetTransform(wid);
			transform.measuredSize = ivec2(1,0);
		}
	}
	void drawWidget(WidgetId wid, ref DrawEvent event) {
		if (event.bubbling) return;
		auto transform = event.ctx.getOrCreate!WidgetTransform(wid);
		event.renderQueue.drawRectFill(vec2(transform.absPos), vec2(transform.size), event.depth, color_wet_asphalt);
	}
}

alias HFill = Fill!true;
alias VFill = Fill!false;

struct Fill(bool horizontal)
{
	static:
	WidgetId create(GuiContext ctx, WidgetId parent)
	{
		static if (horizontal)
			WidgetId fill = ctx.createWidget(parent, hexpand());
		else
			WidgetId fill = ctx.createWidget(parent, vexpand());
		return fill;
	}
}

alias HLayout = LinearLayout!true;
alias VLayout = LinearLayout!false;

struct LinearLayout(bool horizontal)
{
	static:
	WidgetId create(GuiContext ctx, WidgetId parent, int spacing, int padding)
	{
		WidgetId layout = ctx.createWidget(parent);
		attachTo(ctx, layout, spacing, padding);
		return layout;
	}

	void attachTo(GuiContext ctx, WidgetId wid, int spacing, int padding)
	{
		ctx.set(wid, LinearLayoutSettings(spacing, padding));
		ctx.getOrCreate!WidgetEvents(wid).addEventHandlers(&measure, &layout);
	}

	void measure(WidgetId wid, ref MeasureEvent event)
	{
		auto settings = event.ctx.get!LinearLayoutSettings(wid);
		settings.numExpandableChildren = 0;

		int maxChildWidth = int.min;
		int childrenLength;

		WidgetId[] children = event.ctx.widgetChildren(wid);
		foreach(child; children)
		{
			auto childTransform = event.ctx.get!WidgetTransform(child);
			childTransform.applyConstraints();
			childrenLength += length(childTransform.measuredSize);
			maxChildWidth = max(width(childTransform.measuredSize), maxChildWidth);
			if (hasExpandableLength(event.ctx, child)) ++settings.numExpandableChildren;
		}

		int minRootWidth = maxChildWidth + settings.padding*2;
		int minRootLength = childrenLength + cast(int)(children.length-1)*settings.spacing + settings.padding*2;
		auto transform = event.ctx.get!WidgetTransform(wid);
		transform.measuredSize = sizeFromWidthLength(minRootWidth, minRootLength);
	}

	void layout(WidgetId wid, ref LayoutEvent event)
	{
		auto settings = event.ctx.get!LinearLayoutSettings(wid);
		auto rootTransform = event.ctx.get!WidgetTransform(wid);

		int maxChildWidth = width(rootTransform.size) - settings.padding * 2;

		int extraLength = length(rootTransform.size) - length(rootTransform.measuredSize);
		int extraPerWidget = settings.numExpandableChildren > 0 ? extraLength/settings.numExpandableChildren : 0;

		int topOffset = settings.padding;
		topOffset -= settings.spacing; // compensate extra spacing before first child

		foreach(child; event.ctx.widgetChildren(wid))
		{
			topOffset += settings.spacing;
			auto childTransform = event.ctx.get!WidgetTransform(child);
			childTransform.relPos = sizeFromWidthLength(settings.padding, topOffset);
			childTransform.absPos = rootTransform.absPos + childTransform.relPos;

			ivec2 childSize = childTransform.measuredSize;
			if (hasExpandableLength(event.ctx, child)) length(childSize) += extraPerWidget;
			if (hasExpandableWidth(event.ctx, child)) width(childSize) = maxChildWidth;
			childTransform.size = childSize;

			topOffset += length(childSize);
		}
	}

	private:

	bool hasExpandableWidth(GuiContext ctx, WidgetId wid) {
		static if (horizontal) return ctx.has!vexpand(wid);
		else return ctx.has!hexpand(wid);
	}

	bool hasExpandableLength(GuiContext ctx, WidgetId wid) {
		static if (horizontal) return ctx.has!hexpand(wid);
		else return ctx.has!vexpand(wid);
	}

	ivec2 sizeFromWidthLength(int width, int length) {
		static if (horizontal) return ivec2(length, width);
		else return ivec2(width, length);
	}

	ref int length(return ref ivec2 vector) {
		static if (horizontal) return vector.x;
		else return vector.y;
	}

	ref int width(ref ivec2 vector) {
		static if (horizontal) return vector.y;
		else return vector.x;
	}
}

struct ColumnInfo
{
	string name;
	int width = 100;
	Alignment alignment;
	enum int minWidth = 80;
}

interface ListModel
{
	int numLines();
	int numColumns();
	ref ColumnInfo columnInfo(int column);
	void getColumnText(int column, scope void delegate(const(char)[]) sink);
	void getCellText(int column, int row, scope void delegate(const(char)[]) sink);
	bool isLineSelected(int row);
	void onLineClick(int row);
}

@Component("gui.ListData", Replication.none)
struct ListData
{
	ListModel model;
	FontRef font;
	ivec2 headerPadding = ivec2(5, 5);
	ivec2 contentPadding = ivec2(5, 2);
	enum scrollSpeedLines = 1;
	int hoveredLine = -1;
	ivec2 viewOffset; // on canvas

	bool hasHoveredLine() { return hoveredLine >= 0 && hoveredLine < model.numLines; }
	int textHeight() { return font.metrics.height; }
	int lineHeight() { return textHeight + contentPadding.y*2; }
	int headerHeight() { return textHeight + headerPadding.y*2; }
	int canvasHeight() { return lineHeight * model.numLines; }
}

struct ColumnListLogic
{
	static:
	WidgetId create(GuiContext ctx, WidgetId parent, ListModel model, FontRef font)
	{
		WidgetId list = ctx.createWidget(parent,
			ListData(model, font),
			hexpand(), vexpand(),
			WidgetEvents(
				&drawWidget, &pointerMoved, &pointerPressed, &pointerReleased,
				&enterWidget, &leaveWidget, &clickWidget, &onScroll),
			WidgetTransform(ivec2(), ivec2(), ivec2()),
			WidgetStyle(baseColor),
			WidgetRespondsToPointer());
		return list;
	}

	void drawWidget(WidgetId wid, ref DrawEvent event)
	{
		if (event.bubbling) return;

		auto data = event.ctx.get!ListData(wid);
		auto transform = event.ctx.getOrCreate!WidgetTransform(wid);
		auto style = event.ctx.get!WidgetStyle(wid);
		event.ctx.debugText.putfln("%s", *transform);

		int numLines = data.model.numLines;
		int numColumns = data.model.numColumns;

		int textHeight = data.textHeight;
		int lineHeight = data.lineHeight;
		int headerHeight = data.headerHeight;
		int canvasHeight = lineHeight * data.model.numLines;

		// calc content size in pixels
		ivec2 canvasSize;
		canvasSize.y = lineHeight * numLines;
		foreach(column; 0..numColumns)
			canvasSize.x += data.model.columnInfo(column).width;
		int lastLine = numLines ? numLines-1 : 0;

		// calc visible lines
		data.viewOffset = vector_clamp(data.viewOffset, ivec2(0, 0), canvasSize);
		int firstVisibleLine = clamp(data.viewOffset.y / lineHeight, 0, lastLine);
		int viewEndPos = data.viewOffset.y + canvasSize.y;
		int lastVisibleLine = clamp(viewEndPos / lineHeight, 0, lastLine);

		bool isLineHovered(int line) { return data.hoveredLine == line; }

		void drawBackground()
		{
			int lineY = transform.absPos.y + headerHeight;
			foreach(line; firstVisibleLine..lastVisibleLine+1)
			{
				auto color_selected = rgb(217, 235, 249);

				Color4ub color;
				if (data.model.isLineSelected(line)) color = color_selected;
				else if (isLineHovered(line)) color = color_selected;
				else color = color_white;//line % 2 ? color_clouds : color_silver;

				event.renderQueue.drawRectFill(
					vec2(transform.absPos.x, lineY),
					vec2(transform.size.x, lineHeight),
					event.depth, color);
				lineY += lineHeight;
			}
		}

		void drawColumnHeader(int column, ivec2 pos, ivec2 size)
		{
			auto params = event.renderQueue.startTextAt(vec2(pos));
			params.color = color_wet_asphalt;
			params.depth = event.depth+2;
			params.monospaced = true;
			params.scissors = irect(pos, size);
			params.meshText(data.model.columnInfo(column).name);
		}

		void drawCell(int column, int line, ivec2 pos, ivec2 size)
		{
			auto params = event.renderQueue.startTextAt(vec2(pos));
			params.color = color_wet_asphalt;
			params.depth = event.depth+2;
			params.monospaced = true;
			params.scissors = irect(pos, size);

			void sinkHandler(const(char)[] str) {
				params.meshText(str);
			}

			data.model.getCellText(column, line, &sinkHandler);
			params.alignMeshedText(data.model.columnInfo(column).alignment, Alignment.min, size);
		}

		drawBackground();

		int colX = transform.absPos.x;
		// columns
		foreach(column; 0..data.model.numColumns)
		{
			int colW = data.model.columnInfo(column).width;
			int cellW = colW - data.contentPadding.x*2;

			// separator
			ivec2 separatorStart = ivec2(colX + colW-1, transform.absPos.y);
			event.renderQueue.drawRectFill(vec2(separatorStart), vec2(1, headerHeight), event.depth+3, color_wet_asphalt);

			// clip
			//event.renderQueue.pushClipRect(irect(cellX, cellY, cellW, transform.size.y));

			// header
			ivec2 headerPos  = ivec2(colX, transform.absPos.y) + data.headerPadding;
			ivec2 headerSize = ivec2(colW, headerHeight) - data.headerPadding*2;
			drawColumnHeader(column, headerPos, headerSize);
			int lineY = transform.absPos.y + headerHeight;

			// cells
			foreach(line; firstVisibleLine..lastVisibleLine+1)
			{
				ivec2 cellPos = ivec2(colX, lineY);
				ivec2 cellSize = ivec2(colW, lineHeight);

				ivec2 cellContentPos = cellPos + data.contentPadding;
				ivec2 cellContentSize = cellSize - data.contentPadding*2;

				drawCell(column, line, cellContentPos, cellContentSize);
				lineY += lineHeight;
			}

			//event.renderQueue.popClipRect();
			colX += colW;
		}

		event.depth += 3;
	}

	void updateHoveredLine(GuiContext ctx, WidgetId wid, ivec2 pointerPos)
	{
		auto transform = ctx.getOrCreate!WidgetTransform(wid);
		auto data = ctx.get!ListData(wid);
		int localPointerY = pointerPos.y - transform.absPos.y;
		int viewY = localPointerY - data.headerHeight;
		double canvasY = viewY + data.viewOffset.y;
		data.hoveredLine = cast(int)floor(canvasY / data.lineHeight);
		if (data.hoveredLine < 0 || data.hoveredLine >= data.model.numLines)
			data.hoveredLine = -1;
	}

	void onScroll(WidgetId wid, ref ScrollEvent event)
	{
		auto data = event.ctx.get!ListData(wid);
		data.viewOffset += ivec2(event.delta * data.scrollSpeedLines * data.lineHeight);
	}

	void pointerMoved(WidgetId wid, ref PointerMoveEvent event)
	{
		updateHoveredLine(event.ctx, wid, event.newPointerPos);
		event.handled = true;
	}

	void pointerPressed(WidgetId wid, ref PointerPressEvent event)
	{
		event.handled = true;
	}

	void pointerReleased(WidgetId wid, ref PointerReleaseEvent event)
	{
		event.handled = true;
	}

	void enterWidget(WidgetId wid, ref PointerEnterEvent event)
	{
		//updateHoveredLine(event.ctx, wid, event.pointerPosition);
	}

	void leaveWidget(WidgetId wid, ref PointerLeaveEvent event)
	{
		//updateHoveredLine(event.ctx, wid, event.pointerPosition);
	}

	void clickWidget(WidgetId wid, ref PointerClickEvent event)
	{
		auto data = event.ctx.get!ListData(wid);
		if (data.hasHoveredLine) data.model.onLineClick(data.hoveredLine);
	}
}
