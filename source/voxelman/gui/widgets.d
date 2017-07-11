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
	WidgetId createPanel(GuiContext ctx, WidgetId parent, ivec2 pos, ivec2 size, Color4ub color)
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
			vec2 linePos = vec2(transform.absPos.x+transform.size.x, 0);
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
	WidgetId createButton(GuiContext ctx, WidgetId parent, string text, FontRef font, ClickHandler handler)
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

			auto mesherParams = event.renderQueue.startTextAt(vec2(transform.absPos) + vec2(transform.size/2));
			mesherParams.font = data.font;
			mesherParams.depth = event.depth+1;
			mesherParams.color = color_wet_asphalt;
			mesherParams.meshTextAligned(data.text, Alignment.center, Alignment.center);

			event.renderQueue.drawRectFill(vec2(transform.absPos), vec2(transform.size), event.depth, buttonColors[data.data]);
			event.depth += 2;
		}
	}

	void pointerMoved(WidgetId wid, ref PointerMoveEvent event) { event.handled = true; }

	void pointerPressed(WidgetId wid, ref PointerPressEvent event)
	{
		//writefln("press %s", wid);
		event.ctx.get!TextButtonData(wid).data |= BUTTON_PRESSED;
		event.handled = true;
	}

	void pointerReleased(WidgetId wid, ref PointerReleaseEvent event)
	{
		//writefln("release %s", wid);
		event.ctx.get!TextButtonData(wid).data &= ~BUTTON_PRESSED;
		event.handled = true;
	}

	void enterWidget(WidgetId wid, ref PointerEnterEvent event)
	{
		//writefln("enter %s", wid);
		event.ctx.get!TextButtonData(wid).data |= BUTTON_HOVERED;
	}

	void leaveWidget(WidgetId wid, ref PointerLeaveEvent event)
	{
		//writefln("leave %s", wid);
		event.ctx.get!TextButtonData(wid).data &= ~BUTTON_HOVERED;
	}

	void clickWidget(WidgetId wid, ref PointerClickEvent event)
	{
		//writefln("click %s", wid);
		auto data = event.ctx.get!TextButtonData(wid);
		if (data.handler) data.handler();
	}

	void measure(WidgetId wid, ref MeasureEvent event)
	{
		auto transform = event.ctx.getOrCreate!WidgetTransform(wid);
		auto data = event.ctx.get!TextButtonData(wid);
		TextMesherParams params;
		params.font = data.font;
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
	void attachTo(GuiContext ctx, WidgetId wid, int spacing, int padding)
	{
		ctx.set(wid, LinearLayoutSettings(spacing, padding));
		ctx.getOrCreate!WidgetEvents(wid).addEventHandlers(&measure, &layout);
	}

	void measure(WidgetId wid, ref MeasureEvent event)
	{
		auto settings = event.ctx.get!LinearLayoutSettings(wid);

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
