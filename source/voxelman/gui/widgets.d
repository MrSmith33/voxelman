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
	ctx.widgets.registerComponent!WidgetIndex;
	ctx.widgets.registerComponent!PagedWidgetData;
	ctx.widgets.registerComponent!TextButtonData;
	ctx.widgets.registerComponent!LinearLayoutSettings;
	ctx.widgets.registerComponent!hexpand;
	ctx.widgets.registerComponent!vexpand;
	ctx.widgets.registerComponent!ListData;
}

struct WidgetProxy
{
	WidgetId wid;
	GuiContext ctx;

	alias wid this;

	WidgetProxy set(Components...)(Components components) { ctx.widgets.set(wid, components); return this; }
	C* get(C)() { return ctx.widgets.get!C(wid); }
	C* getOrCreate(C)(C defVal = C.init) { return ctx.widgets.getOrCreate!C(wid, defVal); }
	bool has(C)() { return ctx.widgets.has!C(wid); }
	WidgetProxy remove(C)() { ctx.widgets.remove!C(wid); return this; }
	WidgetProxy createChild(Components...)(Components components) { return ctx.createWidget(wid, components); }
	void addChild(WidgetId child) { ctx.addChild(wid, child); }
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
	WidgetProxy create(WidgetProxy parent, ivec2 pos, ivec2 size, Color4ub color)
	{
		WidgetProxy panel = parent.createChild(
			WidgetEvents(&drawWidget),
			WidgetTransform(pos, size),
			WidgetStyle(color)).set(WidgetType("Panel"));
		return panel;
	}

	void drawWidget(WidgetId wid, ref DrawEvent event)
	{
		if (event.sinking)
		{
			auto transform = event.ctx.getOrCreate!WidgetTransform(wid);
			auto style = event.ctx.get!WidgetStyle(wid);
			event.renderQueue.drawRectFill(vec2(transform.absPos), vec2(transform.size), event.depth, style.color);
			event.depth += 1;
			event.renderQueue.pushClipRect(irect(transform.absPos, transform.size));
		}
		else
		{
			event.renderQueue.popClipRect();
		}
	}
}

@Component("gui.WidgetIndex", Replication.none)
struct WidgetIndex
{
	size_t index;
	WidgetId master;
}

@Component("gui.PagedWidgetData", Replication.none)
struct PagedWidgetData
{
	WidgetId[] pages;
}

struct PagedWidget
{
	static:
	// Move all children to
	void convert(WidgetProxy widget, size_t initialIndex)
	{
		if (auto cont = widget.get!WidgetContainer)
		{
			auto options = cont.children;
			widget.set(PagedWidgetData(options), WidgetEvents(&measure, &layout));
			cont.children = null;
			if (options)
			{
				cont.put(options[initialIndex]);
			}
		}
	}

	void switchPage(WidgetProxy widget, size_t newPage)
	{
		if (auto cont = widget.get!WidgetContainer)
		{
			auto pages = widget.get!PagedWidgetData.pages;
			if (newPage < pages.length)
				cont.children[0] = pages[newPage];
		}
	}

	void attachToButton(WidgetProxy selectorButton, size_t index)
	{
		selectorButton.set(WidgetIndex(index, ));
		selectorButton.getOrCreate!WidgetEvents.addEventHandler(&onButtonClick);
	}

	void onButtonClick(WidgetId wid, ref PointerClickEvent event)
	{
		auto data = event.ctx.get!TextButtonData(wid);
		if (data.handler) data.handler();
	}

	void measure(WidgetId wid, ref MeasureEvent event)
	{
		auto transform = event.ctx.get!WidgetTransform(wid);
		foreach(child; event.ctx.widgetChildren(wid))
		{
			auto childTransform = event.ctx.get!WidgetTransform(child);
			childTransform.applyConstraints();
			transform.measuredSize = childTransform.measuredSize;
		}
	}

	void layout(WidgetId wid, ref LayoutEvent event)
	{
		auto transform = event.ctx.get!WidgetTransform(wid);
		foreach(child; event.ctx.widgetChildren(wid))
		{
			auto childTransform = event.ctx.get!WidgetTransform(child);
			childTransform.relPos = ivec2(0,0);
			childTransform.absPos = transform.absPos;
			childTransform.size = transform.size;
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
	WidgetProxy create(WidgetProxy parent, string text, FontRef font, ClickHandler handler = null)
	{
		WidgetProxy button = parent.createChild(
			TextButtonData(text, font),
			WidgetEvents(
				&drawWidget, &pointerMoved, &pointerPressed, &pointerReleased,
				&enterWidget, &leaveWidget, &measure),
			WidgetTransform(ivec2(), ivec2(), ivec2(0, font.metrics.height)),
			WidgetStyle(baseColor),
			WidgetRespondsToPointer()).set(WidgetType("TextButton"));
		setHandler(button, handler);
		return button;
	}

	void setHandler(WidgetProxy button, ClickHandler handler)
	{
		auto data = button.get!TextButtonData;
		auto events = button.get!WidgetEvents;
		if (!data.handler)
		{
			events.addEventHandler(&clickWidget);
		}
		data.handler = handler;
	}

	void drawWidget(WidgetId wid, ref DrawEvent event)
	{
		if (event.bubbling) return;

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
		event.renderQueue.drawRectLine(vec2(transform.absPos), vec2(transform.size), event.depth+1, rgb(230,230,230));
		event.depth += 2;
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
		WidgetProxy create(WidgetProxy parent) {
			return parent.createChild(hexpand(), WidgetEvents(&drawWidget, &measure)).set(WidgetType("Line"));
		}
		void measure(WidgetId wid, ref MeasureEvent event) {
			auto transform = event.ctx.getOrCreate!WidgetTransform(wid);
			transform.measuredSize = ivec2(0,1);
		}
	} else {
		WidgetProxy create(WidgetProxy parent) {
			return parent.createChild(vexpand(), WidgetEvents(&drawWidget, &measure));
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
	WidgetProxy create(WidgetProxy parent)
	{
		static if (horizontal)
			return parent.createChild(hexpand()).set(WidgetType("Fill"));
		else
			return parent.createChild(vexpand()).set(WidgetType("Fill"));
	}
}

alias HLayout = LinearLayout!true;
alias VLayout = LinearLayout!false;

struct LinearLayout(bool horizontal)
{
	static:
	WidgetProxy create(WidgetProxy parent, int spacing, int padding)
	{
		WidgetProxy layout = parent.createChild().set(WidgetType("LinearLayout"));
		attachTo(layout, spacing, padding);
		return layout;
	}

	void attachTo(WidgetProxy wid, int spacing, int padding)
	{
		wid.set(LinearLayoutSettings(spacing, padding));
		wid.getOrCreate!WidgetEvents.addEventHandlers(&measure, &layout);
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

enum TreeLineType
{
	leaf,
	collapsedNode,
	expandedNode
}

abstract class ListModel
{
	int numLines();
	int numColumns();
	ref ColumnInfo columnInfo(int column);
	void getColumnText(int column, scope void delegate(const(char)[]) sink);
	void getCellText(int column, int line, scope void delegate(const(char)[]) sink);
	bool isLineSelected(int line);
	void onLineClick(int line);
	TreeLineType getLineType(int line) { return TreeLineType.leaf; }
	int getLineIndent(int line) { return 0; }
	void toggleLineFolding(int line) { }
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
	WidgetProxy create(WidgetProxy parent, ListModel model, FontRef font)
	{
		WidgetProxy list = parent.createChild(
			ListData(model, font),
			hexpand(), vexpand(),
			WidgetEvents(
				&drawWidget, &pointerMoved, &pointerPressed, &pointerReleased,
				&enterWidget, &leaveWidget, &clickWidget, &onScroll),
			WidgetStyle(baseColor),
			WidgetRespondsToPointer()).set(WidgetType("List"));
		return list;
	}

	void drawWidget(WidgetId wid, ref DrawEvent event)
	{
		if (event.bubbling) return;

		auto data = event.ctx.get!ListData(wid);
		auto transform = event.ctx.getOrCreate!WidgetTransform(wid);
		auto style = event.ctx.get!WidgetStyle(wid);

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

		// for folding arrow positioning
		int charW = data.font.metrics.advanceX;

		bool isLineHovered(int line) { return data.hoveredLine == line; }

		void drawBackground()
		{
			int lineY = transform.absPos.y + headerHeight;
			foreach(line; firstVisibleLine..lastVisibleLine+1)
			{
				auto color_selected = rgb(217, 235, 249);
				auto color_hovered = rgb(207, 225, 239);

				Color4ub color;
				if (isLineHovered(line)) color = color_hovered;
				else if (data.model.isLineSelected(line)) color = color_selected;
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
			params.font = data.font;
			params.color = color_wet_asphalt;
			params.depth = event.depth+2;
			params.monospaced = true;
			params.scissors = irect(pos, size);
			params.meshText(data.model.columnInfo(column).name);
		}

		void drawCell(int column, int line, irect rect)
		{
			auto params = event.renderQueue.startTextAt(vec2(rect.position));
			params.font = data.font;
			params.color = color_wet_asphalt;
			params.depth = event.depth+2;
			params.monospaced = true;
			params.scissors = rect;

			void sinkHandler(const(char)[] str) {
				params.meshText(str);
			}

			if (column == 0)
			{
				params.origin.x += charW * data.model.getLineIndent(line);
				final switch(data.model.getLineType(line))
				{
					case TreeLineType.leaf: params.meshText("   "); break;
					case TreeLineType.collapsedNode: params.meshText(" ► "); break;
					case TreeLineType.expandedNode: params.meshText(" ▼ "); break;
				}
			}

			data.model.getCellText(column, line, &sinkHandler);
			params.alignMeshedText(data.model.columnInfo(column).alignment, Alignment.min, rect.size);
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
			event.renderQueue.pushClipRect(irect(colX+data.contentPadding.x, transform.absPos.y, cellW, transform.size.y));

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

				drawCell(column, line, irect(cellContentPos, cellContentSize));
				lineY += lineHeight;
			}

			event.renderQueue.popClipRect();
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
		if (data.hasHoveredLine)
		{
			auto line = data.hoveredLine;
			if (data.model.numColumns < 1) return;

			auto lineType = data.model.getLineType(line);
			if (lineType == TreeLineType.leaf)
			{
				data.model.onLineClick(line);
				return;
			}

			int firstColW = data.model.columnInfo(0).width;
			auto transform = event.ctx.getOrCreate!WidgetTransform(wid);
			auto leftBorder = transform.absPos.x + data.contentPadding.x;
			auto indentW = data.font.metrics.advanceX;
			auto buttonStart = leftBorder + indentW * data.model.getLineIndent(line);
			auto buttonW = indentW*3;
			auto buttonEnd = buttonStart + buttonW;
			auto clickX = event.pointerPosition.x;

			if (clickX >= buttonStart && clickX < buttonEnd)
			{
				data.model.toggleLineFolding(line);
			}
			else
				data.model.onLineClick(line);
		}
	}
}
