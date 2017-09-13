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
import datadriven.entityman : EntityManager;

void registerComponents(ref EntityManager widgets)
{
	widgets.registerComponent!CollapsableWidgetData;
	widgets.registerComponent!LinearLayoutSettings;
	widgets.registerComponent!ListData;
	widgets.registerComponent!PagedWidgetData;
	widgets.registerComponent!SingleLayoutSettings;
	widgets.registerComponent!ButtonState;
	widgets.registerComponent!TextData;
	widgets.registerComponent!UserClickHandler;
	widgets.registerComponent!UserCheckHandler;
	widgets.registerComponent!WidgetIndex;
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
	WidgetProxy handlers(Handlers...)(Handlers h) { ctx.widgets.getOrCreate!WidgetEvents(wid).addEventHandlers(h); return this; }
	void addChild(WidgetId child) { ctx.addChild(wid, child); }
}

static struct ChildrenRange
{
	GuiContext ctx;
	WidgetId[] children;
	size_t length(){ return children.length; }
	WidgetProxy opIndex(size_t i) { return WidgetProxy(children[i], ctx); }
	int opApply(scope int delegate(WidgetProxy) del)
	{
		foreach(childId; children)
			if (auto ret = del(WidgetProxy(childId, ctx)))
				return ret;
		return 0;
	}
}


enum baseColor = rgb(26, 188, 156);
enum hoverColor = rgb(22, 160, 133);
enum color_clouds = rgb(236, 240, 241);
enum color_silver = rgb(189, 195, 199);
enum color_concrete = rgb(149, 165, 166);
enum color_asbestos = rgb(127, 140, 141);
enum color_white = rgb(250, 250, 250);
enum color_gray = rgb(241, 241, 241);

enum color_wet_asphalt = rgb(52, 73, 94);

struct FrameParts
{
	WidgetProxy frame;
	alias frame this;
	WidgetProxy header;
	WidgetProxy container;
}

struct Frame
{
	static:
	FrameParts create(WidgetProxy parent)
	{
		WidgetProxy frame = parent.createChild(WidgetType("Frame")).setVLayout(0, 0);
		PanelLogic.attachTo(frame, color_clouds);

		auto header = frame.createChild(WidgetType("Header")).hexpand;
		PanelLogic.attachTo(header, color_white);

		auto container = frame.createChild(WidgetType("Container")).hvexpand;

		return FrameParts(frame, header, container);
	}
}

struct PanelLogic
{
	static:
	void attachTo(WidgetProxy widget, Color4ub color)
	{
		widget.set(WidgetStyle(color)).handlers(&drawWidget);
	}

	WidgetProxy create(WidgetProxy parent, Color4ub color)
	{
		WidgetProxy panel = parent.createChild(
			WidgetEvents(&drawWidget),
			WidgetStyle(color), WidgetType("Panel"));
		return panel;
	}

	void drawWidget(WidgetProxy widget, ref DrawEvent event)
	{
		if (event.sinking) {
			auto transform = widget.getOrCreate!WidgetTransform;
			auto style = widget.get!WidgetStyle;
			event.renderQueue.drawRectFill(vec2(transform.absPos), vec2(transform.size), event.depth, style.color);
			event.depth += 1;
			//event.renderQueue.pushClipRect(irect(transform.absPos, transform.size));
		} else {
			//event.renderQueue.popClipRect();
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
			WidgetId[] pages = cont.children;
			widget.set(PagedWidgetData(pages), WidgetEvents(&measure, &layout));
			cont.children = null;
			if (pages)
			{
				cont.put(pages[initialIndex]);
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
		selectorButton.set(WidgetIndex(index));
		selectorButton.getOrCreate!WidgetEvents.addEventHandler(&onButtonClick);
	}

	void onButtonClick(WidgetProxy widget, ref PointerClickEvent event)
	{
		auto data = widget.get!UserClickHandler;
		data.onClick();
	}

	void measure(WidgetProxy widget, ref MeasureEvent event)
	{
		auto transform = widget.get!WidgetTransform;
		foreach(child; widget.children)
		{
			auto childTransform = child.get!WidgetTransform;
			transform.measuredSize = childTransform.size;
		}
	}

	void layout(WidgetProxy widget, ref LayoutEvent event)
	{
		auto transform = widget.get!WidgetTransform;
		foreach(child; widget.children)
		{
			auto childTransform = child.get!WidgetTransform;
			childTransform.relPos = ivec2(0,0);
			childTransform.size = transform.size;
		}
	}
}

@Component("gui.CollapsableWidgetData", Replication.none)
struct CollapsableWidgetData
{
	WidgetId[] childrenStash;
}

struct CollapsableParts
{
	WidgetProxy collapsable;
	alias collapsable this;
	WidgetProxy header;
	WidgetProxy container;
}

/// On user click toggles
struct CollapsableWidget
{
	static:
	CollapsableParts create(WidgetProxy parent, bool expanded = false)
	{
		auto collapsable = parent.createChild(
			WidgetType("Collapsable")).hexpand;
		VLayout.attachTo(collapsable, 2, 0);

		auto header = collapsable.createChild(
			WidgetType("Header"),
			WidgetRespondsToPointer(),
			ButtonState(),
			WidgetEvents(&onHeaderClick, &drawButtonStateBack, &pointerMoved, &pointerPressed,
					&pointerReleased, &enterWidget, &leaveWidget)).hexpand;

		auto container = collapsable.createChild().hexpand;

		auto cont = collapsable.get!WidgetContainer;
		collapsable.set(CollapsableWidgetData(cont.children));

		if (!expanded) toggle(collapsable);
		return CollapsableParts(collapsable, header, container);
	}

	void onHeaderClick(WidgetProxy header, ref PointerClickEvent event)
	{
		auto tran = header.get!WidgetTransform;
		toggle(WidgetProxy(tran.parent, header.ctx));
	}

	void toggle(WidgetProxy collapsable)
	{
		auto cont = collapsable.get!WidgetContainer;
		if (cont.children.length == 2) {
			cont.children = cont.children[0..1];
		} else {
			auto data = collapsable.get!CollapsableWidgetData;
			cont.children = data.childrenStash;
		}
	}

	mixin ButtonPointerLogic!ButtonState;
}

@Component("gui.TextData", Replication.none)
struct TextData
{
	string text;
	Alignment halign;
	Alignment valign;
}

WidgetProxy createText(
	WidgetProxy parent,
	string text,
	FontRef font,
	Alignment halign = Alignment.center,
	Alignment valign = Alignment.center)
{
	TextMesherParams params;
	params.font = font;
	params.monospaced = true;
	measureText(params, text);

	WidgetProxy textWidget = parent.createChild(
		TextData(text, halign, valign),
		WidgetEvents(&drawText),
		WidgetType("Text"))
			.minSize(0, font.metrics.height)
			.measuredSize(ivec2(params.size));
	return textWidget;
}

void drawText(WidgetProxy widget, ref DrawEvent event)
{
	if (event.bubbling) return;

	auto data = widget.get!TextData;
	auto transform = widget.getOrCreate!WidgetTransform;
	auto alignmentOffset = textAlignmentOffset(transform.measuredSize, data.halign, data.valign, transform.size);

	auto params = event.renderQueue.startTextAt(vec2(transform.absPos));
	params.monospaced = true;
	params.depth = event.depth;
	params.color = color_wet_asphalt;
	params.origin += alignmentOffset;
	params.meshText(data.text);

	event.depth += 1;
}

enum BUTTON_PRESSED = 0b0001;
enum BUTTON_HOVERED = 0b0010;
enum BUTTON_SELECTED = 0b0100;

enum buttonNormalColor = rgb(255, 255, 255);
enum buttonHoveredColor = rgb(241, 241, 241);
enum buttonPressedColor = rgb(229, 229, 229);
Color4ub[4] buttonColors = [buttonNormalColor, buttonNormalColor, buttonHoveredColor, buttonPressedColor];

@Component("gui.ButtonState", Replication.none)
struct ButtonState
{
	uint data;
}

struct TextButtonLogic
{
	static:
	WidgetProxy create(WidgetProxy parent, string text, FontRef font, ClickHandler handler = null)
	{
		WidgetProxy button = parent.createChild(
			UserClickHandler(), ButtonState(),
			WidgetEvents(
				&drawButtonStateBack, &pointerMoved, &pointerPressed,
				&pointerReleased, &enterWidget, &leaveWidget),
			WidgetRespondsToPointer(),
			WidgetType("TextButton"));

		button.createText(text, font);
		setHandler(button, handler);
		SingleLayout.attachTo(button, 2);

		return button;
	}


	mixin ButtonPointerLogic!ButtonState;
	mixin ButtonClickLogic!UserClickHandler;
}

void drawButtonStateBack(WidgetProxy widget, ref DrawEvent event)
{
	if (event.bubbling) return;

	auto state = widget.get!ButtonState;
	auto transform = widget.getOrCreate!WidgetTransform;

	event.renderQueue.drawRectFill(vec2(transform.absPos), vec2(transform.size), event.depth, buttonColors[state.data & 0b11]);
	//event.renderQueue.drawRectLine(vec2(transform.absPos), vec2(transform.size), event.depth+1, rgb(230,230,230));
	event.depth += 1;
}

/// Assumes that parent has ToggleButtonData data and uses its data and isChecked fields
struct CheckIconLogic
{
	static:
	WidgetProxy create(WidgetProxy parent, ivec2 size)
	{
		WidgetTransform t;
		t.measuredSize = size;
		return parent.createChild(t, WidgetEvents(&drawWidget), WidgetType("CheckIcon"));
	}

	void drawWidget(WidgetProxy widget, ref DrawEvent event)
	{
		if (event.bubbling) return;

		auto tran = widget.getOrCreate!WidgetTransform;
		auto parentData = widget.ctx.get!UserCheckHandler(tran.parent);
		auto parentState = widget.ctx.get!ButtonState(tran.parent);

		event.renderQueue.drawRectFill(vec2(tran.absPos), vec2(tran.size), event.depth, buttonColors[parentState.data & 0b11]);
		if (parentData.isChecked)
			event.renderQueue.drawRectFill(vec2(tran.absPos + 2), vec2(tran.size - 4), event.depth+1, color_wet_asphalt);
		event.renderQueue.drawRectLine(vec2(tran.absPos), vec2(tran.size), event.depth+1, color_wet_asphalt);
		event.depth += 2;
	}
}

struct CheckButtonLogic
{
	static:
	WidgetProxy create(WidgetProxy parent, string text, FontRef font, CheckHandler handler = null)
	{
		WidgetProxy check = parent.createChild(
			UserCheckHandler(), ButtonState(),
			WidgetEvents(&pointerMoved, &pointerPressed, &pointerReleased, &enterWidget, &leaveWidget),
			WidgetRespondsToPointer(),
			WidgetType("CheckButton"));

		auto iconSize = font.metrics.height;
		auto icon = CheckIconLogic.create(check, ivec2(iconSize, iconSize));

		check.createText(text, font);

		setHandler(check, handler);
		HLayout.attachTo(check, 2, 2);

		return check;
	}

	mixin ButtonPointerLogic!ButtonState;
	mixin ButtonClickLogic!UserCheckHandler;
}

mixin template ButtonPointerLogic(State)
{
	static:
	void pointerMoved(WidgetProxy widget, ref PointerMoveEvent event) { event.handled = true; }

	void pointerPressed(WidgetProxy widget, ref PointerPressEvent event)
	{
		widget.get!State.data |= BUTTON_PRESSED;
		event.handled = true;
	}

	void pointerReleased(WidgetProxy widget, ref PointerReleaseEvent event)
	{
		widget.get!State.data &= ~BUTTON_PRESSED;
		event.handled = true;
	}

	void enterWidget(WidgetProxy widget, ref PointerEnterEvent event)
	{
		widget.get!State.data |= BUTTON_HOVERED;
	}

	void leaveWidget(WidgetProxy widget, ref PointerLeaveEvent event)
	{
		widget.get!State.data &= ~BUTTON_HOVERED;
	}
}

alias CheckHandler = ref bool delegate();

@Component("gui.UserCheckHandler", Replication.none)
struct UserCheckHandler
{
	CheckHandler handler;
	void onClick() { if (handler) toggle_bool(handler()); }
	bool isChecked() { return handler ? handler() : false; }
}

alias ClickHandler = void delegate();

@Component("gui.UserClickHandler", Replication.none)
struct UserClickHandler
{
	void onClick() { if (handler) handler(); }
	ClickHandler handler;
}

mixin template ButtonClickLogic(Data)
{
	void clickWidget(WidgetProxy widget, ref PointerClickEvent event)
	{
		auto data = widget.get!Data;
		data.onClick();
	}

	void setHandler(WidgetProxy button, typeof(Data.handler) handler) {
		auto data = button.get!Data;
		auto events = button.get!WidgetEvents;
		if (!data.handler) events.addEventHandler(&clickWidget);
		data.handler = handler;
	}
}

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
			return parent.createChild(WidgetEvents(&drawWidget, &measure), WidgetType("HLine")).hexpand;
		}
		void measure(WidgetProxy widget, ref MeasureEvent event) {
			auto transform = widget.getOrCreate!WidgetTransform;
			transform.measuredSize = ivec2(0,1);
		}
	} else {
		WidgetProxy create(WidgetProxy parent) {
			return parent.createChild(WidgetEvents(&drawWidget, &measure), WidgetType("VLine")).vexpand;
		}
		void measure(WidgetProxy widget, ref MeasureEvent event) {
			auto transform = widget.getOrCreate!WidgetTransform;
			transform.measuredSize = ivec2(1,0);
		}
	}
	void drawWidget(WidgetProxy widget, ref DrawEvent event) {
		if (event.bubbling) return;
		auto transform = widget.getOrCreate!WidgetTransform;
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
			return parent.createChild(WidgetType("Fill")).hexpand;
		else
			return parent.createChild(WidgetType("Fill")).vexpand;
	}
}

WidgetProxy moveToTop(WidgetProxy widget) {
	AutoMoveToTop.attachTo(widget);
	return widget;
}
struct AutoMoveToTop
{
	static void attachTo(WidgetProxy widget)
	{
		widget.handlers(&onPress);
	}
	static void onPress(WidgetProxy widget, ref PointerPressEvent event)
	{
		auto parentId = widget.get!WidgetTransform.parent;
		if (parentId)
		{
			if (auto children = widget.ctx.get!WidgetContainer(parentId))
			{
				children.bringToFront(widget.wid);
			}
		}
	}
}

WidgetProxy makeDraggable(WidgetProxy widget) { DraggableLogic.attachTo(widget); return widget; }

struct DraggableLogic
{
	static:
	void attachTo(WidgetProxy widget)
	{
		widget.handlers(&onPress, &onDrag);
	}

	void onPress(WidgetProxy widget, ref PointerPressEvent event)
	{
		if (event.sinking) return;

		event.handled = true;
		event.beginDrag = true;
	}

	void onDrag(WidgetProxy widget, ref DragEvent event)
	{
		widget.get!WidgetTransform.relPos += event.delta;
	}
}

@Component("gui.SingleLayoutSettings", Replication.none)
struct SingleLayoutSettings
{
	int padding; /// borders around items
	Alignment halign;
	Alignment valign;
}

WidgetProxy setSingleLayout(WidgetProxy widget, int padding, Alignment halign = Alignment.center, Alignment valign = Alignment.center)
{
	SingleLayout.attachTo(widget, padding, halign, valign);
	return widget;
}

/// For layouting single child with alignment and padding.
struct SingleLayout
{
	static:
	void attachTo(
		WidgetProxy widget,
		int padding,
		Alignment halign = Alignment.center,
		Alignment valign = Alignment.center)
	{
		widget.set(SingleLayoutSettings(padding, halign, valign));
		widget.handlers(&measure, &layout);
	}

	void measure(WidgetProxy widget, ref MeasureEvent event)
	{
		auto settings = widget.get!SingleLayoutSettings;
		ivec2 childSize;

		ChildrenRange children = widget.children;
		if (children.length > 0)
		{
			auto childTransform = children[0].get!WidgetTransform;
			childSize = childTransform.size;
		}

		widget.get!WidgetTransform.measuredSize = childSize + settings.padding*2;
	}

	void layout(WidgetProxy widget, ref LayoutEvent event)
	{
		auto settings = widget.get!SingleLayoutSettings;
		auto rootTransform = widget.get!WidgetTransform;

		ivec2 childArea = rootTransform.size - settings.padding * 2;

		ChildrenRange children = widget.children;
		if (children.length > 0)
		{
			WidgetProxy child = children[0];
			auto childTransform = child.get!WidgetTransform;

			ivec2 childSize;
			ivec2 relPos;

			//widget.ctx.debugText.putfln("SLayout.layout %s tr %s",
			//	widget.wid, *childTransform);

			if (childTransform.hasVexpand) {
				childSize.x = childArea.x;
				relPos.x = settings.padding;
			} else {
				childSize.x = childTransform.measuredSize.x;
				relPos.x = settings.padding + alignOnAxis(childSize.x, settings.halign, childArea.x);
			}

			if (childTransform.hasHexpand) {
				childSize.y = childArea.y;
				relPos.y = settings.padding;
			} else {
				childSize.y = childTransform.measuredSize.y;
				relPos.y = settings.padding + alignOnAxis(childSize.y, settings.valign, childArea.y);
			}

			childTransform.relPos = relPos;
			childTransform.size = childSize;
		}
	}
}

alias HLayout = LinearLayout!true;
alias VLayout = LinearLayout!false;

alias setHLayout = setLinearLayout!true;
alias setVLayout = setLinearLayout!false;

WidgetProxy setLinearLayout(bool hori)(WidgetProxy widget, int spacing, int padding)
{
	LinearLayout!hori.attachTo(widget, spacing, padding);
	return widget;
}

struct LinearLayout(bool horizontal)
{
	static:
	WidgetProxy create(WidgetProxy parent, int spacing, int padding)
	{
		WidgetProxy layout = parent.createChild(WidgetType("LinearLayout"));
		attachTo(layout, spacing, padding);
		return layout;
	}

	void attachTo(WidgetProxy widget, int spacing, int padding)
	{
		//writefln("attachTo %s %s", widget.widgetType, widget.wid);
		widget.set(LinearLayoutSettings(spacing, padding));
		widget.getOrCreate!WidgetEvents.addEventHandlers(&measure, &layout);
	}

	void measure(WidgetProxy widget, ref MeasureEvent event)
	{
		auto settings = widget.get!LinearLayoutSettings;
		settings.numExpandableChildren = 0;

		int maxChildWidth = 0;
		int childrenLength;

		ChildrenRange children = widget.children;
		foreach(child; children)
		{
			auto childTransform = child.get!WidgetTransform;
			childrenLength += length(childTransform.size);
			maxChildWidth = max(width(childTransform.size), maxChildWidth);
			if (hasExpandableLength(child)) ++settings.numExpandableChildren;
		}

		int minRootWidth = maxChildWidth + settings.padding*2;
		int minRootLength = childrenLength + cast(int)(children.length-1)*settings.spacing + settings.padding*2;
		auto transform = widget.get!WidgetTransform;
		transform.measuredSize = sizeFromWidthLength(minRootWidth, minRootLength);
	}

	void layout(WidgetProxy widget, ref LayoutEvent event)
	{
		auto settings = widget.get!LinearLayoutSettings;
		auto rootTransform = widget.get!WidgetTransform;

		int maxChildWidth = width(rootTransform.size) - settings.padding * 2;

		int extraLength = length(rootTransform.size) - length(rootTransform.measuredSize);
		int extraPerWidget = settings.numExpandableChildren > 0 ? extraLength/settings.numExpandableChildren : 0;

		int topOffset = settings.padding;
		topOffset -= settings.spacing; // compensate extra spacing before first child

		foreach(child; widget.children)
		{
			topOffset += settings.spacing;
			auto childTransform = child.get!WidgetTransform;
			childTransform.relPos = sizeFromWidthLength(settings.padding, topOffset);

			ivec2 childSize = childTransform.constrainedSize;
			if (hasExpandableLength(child)) length(childSize) += extraPerWidget;
			if (hasExpandableWidth(child)) width(childSize) = maxChildWidth;
			childTransform.size = childSize;

			//widget.ctx.debugText.putfln("LLayout.layout %s tr %s extra %s",
			//	child.wid, *childTransform, extraPerWidget);

			topOffset += length(childSize);
		}
	}

	private:

	bool hasExpandableWidth(WidgetProxy widget) {
		static if (horizontal) return widget.hasVexpand;
		else return widget.hasHexpand;
	}

	bool hasExpandableLength(WidgetProxy widget) {
		static if (horizontal) return widget.hasHexpand;
		else return widget.hasVexpand;
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
			WidgetEvents(
				&drawWidget, &pointerMoved, &pointerPressed, &pointerReleased,
				&enterWidget, &leaveWidget, &clickWidget, &onScroll),
			WidgetStyle(baseColor),
			WidgetRespondsToPointer(), WidgetType("List"));
		return list;
	}

	void drawWidget(WidgetProxy widget, ref DrawEvent event)
	{
		if (event.bubbling) return;

		auto data = widget.get!ListData;
		auto transform = widget.getOrCreate!WidgetTransform;
		auto style = widget.get!WidgetStyle;

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

	void updateHoveredLine(WidgetProxy widget, ivec2 pointerPos)
	{
		auto transform = widget.getOrCreate!WidgetTransform;
		auto data = widget.get!ListData;
		int localPointerY = pointerPos.y - transform.absPos.y;
		int viewY = localPointerY - data.headerHeight;
		double canvasY = viewY + data.viewOffset.y;
		data.hoveredLine = cast(int)floor(canvasY / data.lineHeight);
		if (data.hoveredLine < 0 || data.hoveredLine >= data.model.numLines)
			data.hoveredLine = -1;
	}

	void onScroll(WidgetProxy widget, ref ScrollEvent event)
	{
		auto data = widget.get!ListData;
		data.viewOffset += ivec2(event.delta * data.scrollSpeedLines * data.lineHeight);
	}

	void pointerMoved(WidgetProxy widget, ref PointerMoveEvent event)
	{
		updateHoveredLine(widget, event.newPointerPos);
		event.handled = true;
	}

	void pointerPressed(WidgetProxy widget, ref PointerPressEvent event)
	{
		event.handled = true;
	}

	void pointerReleased(WidgetProxy widget, ref PointerReleaseEvent event)
	{
		event.handled = true;
	}

	void enterWidget(WidgetProxy widget, ref PointerEnterEvent event)
	{
		//updateHoveredLine(widget, event.pointerPosition);
	}

	void leaveWidget(WidgetProxy widget, ref PointerLeaveEvent event)
	{
		//updateHoveredLine(widget, event.pointerPosition);
	}

	void clickWidget(WidgetProxy widget, ref PointerClickEvent event)
	{
		auto data = widget.get!ListData;
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
			auto transform = widget.getOrCreate!WidgetTransform;
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
