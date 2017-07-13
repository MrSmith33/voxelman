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
}

@Component("gui.ListData", Replication.none)
struct ListData
{
	ListModel model;
	enum headerHeight = 25;
	int contentPadding = 5;
	ivec2 viewportPos;
}

struct ColumnListLogic
{
	static:
	WidgetId create(GuiContext ctx, WidgetId parent, ListModel model)
	{
		WidgetId list = ctx.createWidget(parent,
			ListData(model),
			hexpand(), vexpand(),
			WidgetEvents(
				&drawWidget, &pointerMoved, &pointerPressed, &pointerReleased,
				&enterWidget, &leaveWidget, &clickWidget),
			WidgetTransform(ivec2(), ivec2(), ivec2()),
			WidgetStyle(baseColor),
			WidgetRespondsToPointer());
		return list;
	}

	void drawWidget(WidgetId wid, ref DrawEvent event)
	{
		if (event.sinking)
		{
			auto data = event.ctx.get!ListData(wid);
			auto transform = event.ctx.getOrCreate!WidgetTransform(wid);
			auto style = event.ctx.get!WidgetStyle(wid);

			event.renderQueue.drawRectFill(vec2(transform.absPos), vec2(transform.size), event.depth, color_clouds);
			//irect canvas;
			irect viewport = irect(transform.absPos, transform.size);
			event.renderQueue.pushClipRect(viewport);

			void drawCell(ivec2 pos, ivec2 size, int column, int line)
			{
				auto params = event.renderQueue.startTextAt(vec2(pos));
				//params.monospaced = true;
				params.depth = event.depth+2;
				params.color = color_wet_asphalt;

				void sinkHandler(const(char)[] str) {
					params.meshText(str);
				}

				data.model.getCellText(column, line, &sinkHandler);
				params.alignMeshedText(data.model.columnInfo(column).alignment, Alignment.min, size);
			}

			int lineHeight = 14;
			int contentHeight = data.headerHeight + lineHeight * data.model.numLines;
			int colX = transform.absPos.x;

			foreach(column; 0..data.model.numColumns)
			{
				int cellX = colX + data.contentPadding;
				int cellY = transform.absPos.y;

				int colW = data.model.columnInfo(column).width;
				int cellW = colW - data.contentPadding*2;

				// separator
				ivec2 lineStart = colX + colW-1;
				event.renderQueue.drawRectFill(vec2(lineStart), vec2(1, contentHeight), event.depth+3, color_wet_asphalt);
				colX += colW;

				event.renderQueue.pushClipRect(irect(cellX, cellY, cellW, transform.size.y));

				// header
				event.renderQueue.print(
					vec2(cellX, cellY),
					color_wet_asphalt,
					1,
					event.depth+2,
					data.model.columnInfo(column).name);

				cellY += data.headerHeight;

				// cells
				foreach(line; 0..data.model.numLines)
				{
					ivec2 cellPos = ivec2(cellX, cellY);
					drawCell(cellPos, ivec2(cellW, lineHeight), column, line);
					cellY += lineHeight;
				}

				event.renderQueue.popClipRect();
			}

			event.depth += 3;
			event.renderQueue.popClipRect();
		}
	}

	void pointerMoved(WidgetId wid, ref PointerMoveEvent event) { event.handled = true; }

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
	}

	void leaveWidget(WidgetId wid, ref PointerLeaveEvent event)
	{
	}

	void clickWidget(WidgetId wid, ref PointerClickEvent event)
	{
	}
}
