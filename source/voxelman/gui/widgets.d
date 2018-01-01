/**
Copyright: Copyright (c) 2017-2018 Andrey Penechko.
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
	widgets.registerComponent!ButtonState;
	widgets.registerComponent!ChildrenStash;
	widgets.registerComponent!ConditionData;
	widgets.registerComponent!DraggableSettings;
	widgets.registerComponent!DropDownData;
	widgets.registerComponent!IconData;
	widgets.registerComponent!ImageData;
	widgets.registerComponent!LinearLayoutSettings;
	widgets.registerComponent!ListData;
	widgets.registerComponent!ScrollableData;
	widgets.registerComponent!SingleLayoutSettings;
	widgets.registerComponent!TextData;
	widgets.registerComponent!UserCheckHandler;
	widgets.registerComponent!UserClickHandler;
	widgets.registerComponent!WidgetIndex;
	widgets.registerComponent!WidgetReference;
}

@Component("gui.WidgetReference", Replication.none)
struct WidgetReference
{
	WidgetId widgetId;
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
	bool postEvent(Event)(auto ref Event event) { return ctx.postEvent(this, event); }
	void toggleFlag(Component)() { if (ctx.widgets.has!Component(wid)) ctx.widgets.remove!Component(wid); else ctx.widgets.set(wid, Component()); }

	void focus() { ctx.focusedWidget = wid; }
	void unfocus() { ctx.focusedWidget = 0; }
	void setFocus(bool isFocused) { if (isFocused) ctx.focusedWidget = wid; else ctx.focusedWidget = 0; }
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
		{
			if (ctx.widgets.has!hidden(childId)) continue;
			if (auto ret = del(WidgetProxy(childId, ctx)))
				return ret;
		}
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
		WidgetProxy frame = parent.createChild(WidgetType("Frame"))
			.setVLayout(0, padding4(0))
			.addBackground(color_clouds)
			.consumeMouse;

		auto header = frame.createChild(WidgetType("Header"))
			.addBackground(color_white)
			.hexpand;

		auto container = frame.createChild(WidgetType("Container")).hvexpand;

		return FrameParts(frame, header, container);
	}
}

@Component("gui.ConditionData", Replication.none)
struct ConditionData
{
	bool delegate() condition;
	bool invert;
}

WidgetProxy visible_if(WidgetProxy widget, bool delegate() condition)
{
	widget.set(ConditionData(condition)).handlers(&updateVisibility); return widget;
}

WidgetProxy visible_if_not(WidgetProxy widget, bool delegate() condition)
{
	widget.set(ConditionData(condition, true)).handlers(&updateVisibility); return widget;
}

void updateVisibility(WidgetProxy widget, ref GuiUpdateEvent event)
{
	if (event.bubbling) return;
	auto data = widget.get!ConditionData;
	if (data.condition is null) return;
	bool isVisible = data.condition();
	if (data.invert) isVisible = !isVisible;
	if (isVisible)
		widget.remove!hidden;
	else
		widget.set(hidden());
}

WidgetProxy addBackground(WidgetProxy widget, Color4ub color)
{
	widget.getOrCreate!WidgetStyle.color = color;
	widget.handlers(&PanelLogic.drawBackground);
	return widget;
}

WidgetProxy addBorder(WidgetProxy widget, Color4ub color)
{
	widget.getOrCreate!WidgetStyle.borderColor = color;
	widget.handlers(&PanelLogic.drawBorder);
	return widget;
}

struct PanelLogic
{
	static:
	WidgetProxy create(WidgetProxy parent, Color4ub color)
	{
		WidgetProxy panel = parent.createChild(
			WidgetEvents(&drawBackground),
			WidgetStyle(color), WidgetType("Panel"));
		return panel;
	}

	void drawBackground(WidgetProxy widget, ref DrawEvent event)
	{
		if (event.sinking) {
			auto transform = widget.getOrCreate!WidgetTransform;
			auto style = widget.get!WidgetStyle;
			event.renderQueue.drawRectFill(vec2(transform.absPos), vec2(transform.size), event.depth, style.color);
			event.depth += 1;
			event.renderQueue.pushClipRect(irect(transform.absPos, transform.size));
		} else {
			event.renderQueue.popClipRect();
		}
	}

	void drawBorder(WidgetProxy widget, ref DrawEvent event)
	{
		if (event.sinking) {
			auto transform = widget.getOrCreate!WidgetTransform;
			auto style = widget.get!WidgetStyle;
			event.renderQueue.drawRectLine(vec2(transform.absPos), vec2(transform.size), event.depth, style.borderColor);
			event.depth += 1;
		}
	}
}

WidgetProxy createImage(WidgetProxy parent, ImageData data)
{
	return ImageLogic.create(parent, data);
}

@Component("gui.ImageData", Replication.none)
struct ImageData
{
	Texture texture;
	irect subRect;
	int scale;
	Color4ub color = Colors.white;
}

struct ImageLogic
{
	static:
	WidgetProxy create(WidgetProxy parent, ImageData data)
	{
		WidgetProxy image = parent.createChild(
			WidgetEvents(&measure, &drawWidget), data, WidgetType("Image"));
		return image;
	}

	void measure(WidgetProxy widget, ref MeasureEvent event)
	{
		auto transform = widget.get!WidgetTransform;
		auto data = widget.get!ImageData;
		transform.measuredSize = data.subRect.size * data.scale;
	}

	void drawWidget(WidgetProxy image, ref DrawEvent event)
	{
		if (event.sinking) {
			auto transform = image.getOrCreate!WidgetTransform;
			auto data = image.get!ImageData;
			event.renderQueue.texBatch.putRect(frect(transform.absPos, transform.size), frect(data.subRect), event.depth, data.color, data.texture);
			event.depth += 1;
		}
	}
}

@Component("gui.IconData", Replication.none)
struct IconData
{
	SpriteRef sprite;
	Color4ub color;
	Alignment halign;
	Alignment valign;
}

WidgetProxy createIcon(WidgetProxy parent, string iconId, ivec2 size, Color4ub color = Colors.white)
{
	return IconLogic.create(parent, parent.ctx.style.icon(iconId), color).minSize(size);
}

WidgetProxy createIcon(WidgetProxy parent, SpriteRef sprite, ivec2 size, Color4ub color = Colors.white)
{
	return IconLogic.create(parent, sprite, color).minSize(size);
}

WidgetProxy createIcon(WidgetProxy parent, SpriteRef sprite, Color4ub color = Colors.white,
	Alignment halign = Alignment.center, Alignment valign = Alignment.center)
{
	return IconLogic.create(parent, sprite, color, halign, valign);
}

struct IconLogic
{
	static:
	WidgetProxy create(WidgetProxy parent, SpriteRef sprite, Color4ub color = Colors.white,
		Alignment halign = Alignment.center, Alignment valign = Alignment.center)
	{
		WidgetProxy icon = parent.createChild(
			WidgetEvents(&drawWidget), IconData(sprite, color, halign, valign), WidgetType("Icon"))
			.measuredSize(sprite.atlasRect.size);
		return icon;
	}

	void drawWidget(WidgetProxy icon, ref DrawEvent event)
	{
		if (event.sinking) {
			auto transform = icon.getOrCreate!WidgetTransform;
			auto data = icon.get!IconData;
			auto alignmentOffset = rectAlignmentOffset(transform.measuredSize, data.halign, data.valign, transform.size);
			event.renderQueue.draw(*data.sprite, vec2(transform.absPos+alignmentOffset), event.depth, data.color);
			event.depth += 1;
		}
	}
}

@Component("gui.WidgetIndex", Replication.none)
struct WidgetIndex
{
	size_t index;
	WidgetId master;
}

/// Used for widgets that hide some of the children, to store original list of children
@Component("gui.ChildrenStash", Replication.none)
struct ChildrenStash
{
	WidgetId[] widgets;
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
			widget.set(ChildrenStash(pages), WidgetEvents(&measure, &layout));
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
			auto pages = widget.get!ChildrenStash.widgets;
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
		VLayout.attachTo(collapsable, 2, padding4(0));

		auto header = collapsable.createChild(
			WidgetType("Header"),
			ButtonState(),
			WidgetEvents(&onHeaderClick, &drawButtonStateBack, &pointerMoved, &pointerPressed,
					&pointerReleased, &enterWidget, &leaveWidget)).hexpand;

		auto container = collapsable.createChild().hexpand;

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
		collapsable.children[1].toggleFlag!hidden;
	}

	mixin ButtonPointerLogic!ButtonState;
}

@Component("gui.TextData", Replication.none)
struct TextData
{
	string text;
	Alignment halign;
	Alignment valign;
	Color4ub color;
}

WidgetProxy createText(WidgetProxy parent, string text,
	Alignment halign = Alignment.center, Alignment valign = Alignment.center)
{
	return TextLogic.create(parent, text,
		parent.ctx.style.font,
		parent.ctx.style.color,
		halign, valign);
}

struct TextLogic
{
	static:
	WidgetProxy create(
		WidgetProxy parent,
		string text,
		FontRef font,
		Color4ub color,
		Alignment halign,
		Alignment valign)
	{
		WidgetProxy textWidget = parent.createChild(
			TextData(text, halign, valign, color),
			WidgetEvents(&drawText),
			WidgetType("Text"))
				.minSize(0, font.metrics.height);
		setText(textWidget, text);
		return textWidget;
	}

	void setText(WidgetProxy widget, string text)
	{
		auto data = widget.get!TextData;
		data.text = text;

		TextMesherParams params;
		params.font = widget.ctx.style.font;
		params.monospaced = false;
		measureText(params, text);

		widget.measuredSize(ivec2(params.size));
	}

	void drawText(WidgetProxy widget, ref DrawEvent event)
	{
		if (event.bubbling) return;

		auto data = widget.get!TextData;
		auto transform = widget.getOrCreate!WidgetTransform;
		auto alignmentOffset = rectAlignmentOffset(transform.measuredSize, data.halign, data.valign, transform.size);

		auto params = event.renderQueue.startTextAt(vec2(transform.absPos));
		params.monospaced = false;
		params.depth = event.depth;
		params.color = data.color;
		params.origin += alignmentOffset;
		params.meshText(data.text);

		event.depth += 1;
	}
}

enum BUTTON_PRESSED = 0b0001;
enum BUTTON_HOVERED = 0b0010;
enum BUTTON_SELECTED = 0b0100;

enum buttonNormalColor = rgb(255, 255, 255);
enum buttonHoveredColor = rgb(241, 241, 241);
enum buttonPressedColor = rgb(229, 229, 229);
enum buttonSelectedColor = rgb(229, 229, 255);
Color4ub[8] buttonColors = [
buttonNormalColor, buttonNormalColor,
buttonHoveredColor, buttonPressedColor,
buttonSelectedColor, buttonSelectedColor,
buttonSelectedColor, buttonSelectedColor];

@Component("gui.ButtonState", Replication.none)
struct ButtonState
{
	uint data;
	bool pressed() { return (data & BUTTON_PRESSED) != 0; }
	bool hovered() { return (data & BUTTON_HOVERED) != 0; }
	bool selected() { return (data & BUTTON_SELECTED) != 0; }
	void toggleSelected() { data = data.toggle_flag(BUTTON_SELECTED); }
}

WidgetProxy createIconTextButton(WidgetProxy parent, SpriteRef icon, string text, ClickHandler handler = null) {
	return IconTextButtonLogic.create(parent, icon, text, handler);
}
WidgetProxy createIconTextButton(WidgetProxy parent, string iconId, string text, ClickHandler handler = null) {
	return IconTextButtonLogic.create(parent, parent.ctx.style.icon(iconId), text, handler);
}

struct IconTextButtonLogic
{
	static:
	WidgetProxy create(WidgetProxy parent, SpriteRef icon, string text, ClickHandler handler = null)
	{
		WidgetProxy button = parent.createChild(
			UserClickHandler(), ButtonState(),
			WidgetEvents(
				&drawButtonStateBack, &pointerMoved, &pointerPressed,
				&pointerReleased, &enterWidget, &leaveWidget),
			WidgetType("IconTextButton"))
			.setHLayout(2, padding4(2), Alignment.center);

		button.createIcon(icon, ivec2(16, 16), Colors.black);
		button.createText(text);
		setHandler(button, handler);

		return button;
	}

	mixin ButtonPointerLogic!ButtonState;
	mixin ButtonClickLogic!UserClickHandler;
}

WidgetProxy createTextButton(WidgetProxy parent, string text, ClickHandler handler = null) {
	return TextButtonLogic.create(parent, text, handler);
}

struct TextButtonLogic
{
	static:
	WidgetProxy create(WidgetProxy parent, string text, ClickHandler handler = null)
	{
		WidgetProxy button = parent.createChild(
			UserClickHandler(), ButtonState(),
			WidgetEvents(
				&drawButtonStateBack, &pointerMoved, &pointerPressed,
				&pointerReleased, &enterWidget, &leaveWidget),
			WidgetType("TextButton"));

		button.createText(text);
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

	event.renderQueue.drawRectFill(vec2(transform.absPos), vec2(transform.size), event.depth, buttonColors[state.data & 0b111]);
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

WidgetProxy createCheckButton(WidgetProxy parent, string text, CheckHandler handler = null) {
	return CheckButtonLogic.create(parent, text, handler);
}

WidgetProxy createCheckButton(WidgetProxy parent, string text, bool* flag) {
	alias Del = ref bool delegate();
	alias Fun = ref bool function();
	Del dg;
	dg.ptr = flag;
	dg.funcptr = cast(Fun)&bool_delegate;
	return CheckButtonLogic.create(parent, text, dg);
}

ref bool bool_delegate(bool* value)
{
	return *value;
}

struct CheckButtonLogic
{
	static:
	WidgetProxy create(WidgetProxy parent, string text, CheckHandler handler = null)
	{
		WidgetProxy check = parent.createChild(
			UserCheckHandler(), ButtonState(),
			WidgetEvents(&pointerMoved, &pointerPressed, &pointerReleased, &enterWidget, &leaveWidget),
			WidgetType("CheckButton"));

		auto iconSize = parent.ctx.style.font.metrics.height;
		auto icon = CheckIconLogic.create(check, ivec2(iconSize, iconSize));

		check.createText(text);

		setHandler(check, handler);
		HLayout.attachTo(check, 2, padding4(2));

		return check;
	}

	mixin ButtonPointerLogic!ButtonState;
	mixin ButtonClickLogic!UserCheckHandler;
}

alias OptionSelectHandler = void delegate(size_t);
@Component("gui.DropDownData", Replication.none)
struct DropDownData
{
	OptionSelectHandler handler;
	void onClick(size_t index) {
		if (selectedOption == index) return;
		selectedOption = index;
		if (handler) handler(selectedOption);
	}
	string[] options;
	size_t selectedOption;
	string optionText() { return options[selectedOption]; }
}

struct DropDown
{
	static:
	WidgetProxy create(WidgetProxy parent, string[] options, size_t selectedOption, OptionSelectHandler handler = null)
	{
		WidgetProxy dropdown = BaseButton.create(parent)
			.handlers(&drawButtonStateBack, &onWidgetClick)
			.set(
				WidgetType("DropDown"),
				DropDownData(handler, options, selectedOption))
			.setHLayout(0, padding4(2), Alignment.center);

		dropdown.createText(options[selectedOption]);
		dropdown.hfill;
		dropdown.createIcon(parent.ctx.style.icon("arrow-up-down"), ivec2(16, 16), Colors.black);

		return dropdown;
	}

	void onWidgetClick(WidgetProxy widget, ref PointerClickEvent event)
	{
		toggleDropDown(widget);
	}

	void toggleDropDown(WidgetProxy widget)
	{
		auto tr = widget.get!WidgetTransform;
		auto data = widget.get!DropDownData;
		auto state = widget.get!ButtonState;
		state.toggleSelected;

		if (state.selected)
		{
			auto optionsOverlay = widget.ctx.createOverlay
				.consumeMouse
				.handlers(&onOverlayPress)
				.set(WidgetReference(widget));

			widget.set(WidgetReference(optionsOverlay));

			auto options = optionsOverlay.createChild()
				.pos(tr.absPos+ivec2(0, tr.size.y))
				.addBackground(color_gray)
				.minSize(tr.size.x, 0)
				.setVLayout(2, padding4(2));

			foreach(i, option; data.options)
			{
				auto button = BaseButton.create(options)
					.set(WidgetIndex(i, widget), WidgetType("DropDownOption"))
					.handlers(&onOptionClick, &drawButtonStateBack)
					.hexpand
					.setSingleLayout(2, Alignment.min);
				button.createText(option);
			}
		}
		else
		{
			auto overlayRef = widget.get!WidgetReference;
			widget.ctx.removeWidget(overlayRef.widgetId);
			widget.remove!WidgetReference;
		}
	}

	void onOverlayPress(WidgetProxy overlay, ref PointerPressEvent event)
	{
		if (event.sinking) return;
		auto dropdownRef = overlay.get!WidgetReference;
		toggleDropDown(WidgetProxy(dropdownRef.widgetId, overlay.ctx));
		event.handled = true;
	}

	void onOptionClick(WidgetProxy option, ref PointerClickEvent event)
	{
		auto index = option.get!WidgetIndex;
		auto dropdown = WidgetProxy(index.master, option.ctx);

		auto data = dropdown.get!DropDownData;
		data.onClick(index.index);
		toggleDropDown(dropdown);
		TextLogic.setText(dropdown.children[0], data.optionText);
	}

	mixin ButtonPointerLogic!ButtonState;
}

struct BaseButton
{
	static:
	WidgetProxy create(WidgetProxy parent)
	{
		return parent.createChild(ButtonState(),
			WidgetEvents(
				&pointerMoved, &pointerPressed,
				&pointerReleased, &enterWidget, &leaveWidget),
			WidgetType("BaseButton"));
	}
	mixin ButtonPointerLogic!ButtonState;
}

mixin template ButtonPointerLogic(State)
{
	static:
	void pointerMoved(WidgetProxy widget, ref PointerMoveEvent event) { event.handled = true; }

	void pointerPressed(WidgetProxy widget, ref PointerPressEvent event)
	{
		if (event.sinking) return;
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

@Component("gui.BoolBinding", Replication.none)
struct BoolBinding
{
	bool* value;
}

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

/// Widget will catch mouse events from bubbling
WidgetProxy consumeMouse(WidgetProxy widget) { widget.handlers(&handlePointerMoved); return widget; }

void handlePointerMoved(WidgetProxy widget, ref PointerMoveEvent event) { event.handled = true; }

WidgetProxy hline(WidgetProxy parent) { HLine.create(parent); return parent; }
WidgetProxy vline(WidgetProxy parent) { VLine.create(parent); return parent; }

alias HLine = Line!true;
alias VLine = Line!false;

struct Line(bool horizontal)
{
	static:
	static if (horizontal) {
		WidgetProxy create(WidgetProxy parent) {
			return parent.createChild(WidgetEvents(&drawWidget, &measure), WidgetType("HLine"), WidgetStyle(parent.ctx.style.color)).hexpand;
		}
		void measure(WidgetProxy widget, ref MeasureEvent event) {
			auto transform = widget.getOrCreate!WidgetTransform;
			transform.measuredSize = ivec2(0,1);
		}
	} else {
		WidgetProxy create(WidgetProxy parent) {
			return parent.createChild(WidgetEvents(&drawWidget, &measure), WidgetType("VLine"), WidgetStyle(parent.ctx.style.color)).vexpand;
		}
		void measure(WidgetProxy widget, ref MeasureEvent event) {
			auto transform = widget.getOrCreate!WidgetTransform;
			transform.measuredSize = ivec2(1,0);
		}
	}
	void drawWidget(WidgetProxy widget, ref DrawEvent event) {
		if (event.bubbling) return;
		auto transform = widget.getOrCreate!WidgetTransform;
		auto color = widget.get!WidgetStyle.color;
		event.renderQueue.drawRectFill(vec2(transform.absPos), vec2(transform.size), event.depth, color);
	}
}

WidgetProxy hfill(WidgetProxy parent) { HFill.create(parent); return parent; }
WidgetProxy vfill(WidgetProxy parent) { VFill.create(parent); return parent; }

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

@Component("DraggableSettings", Replication.none)
struct DraggableSettings
{
	PointerButton onButton;
}

WidgetProxy makeDraggable(WidgetProxy widget, PointerButton onButton = PointerButton.PB_1) {
	DraggableLogic.attachTo(widget, onButton); return widget; }

struct DraggableLogic
{
	static:
	void attachTo(WidgetProxy widget, PointerButton onButton)
	{
		widget.handlers(&onPress, &onDrag).set(DraggableSettings(onButton));
	}

	void onPress(WidgetProxy widget, ref PointerPressEvent event)
	{
		if (event.sinking) return;
		if (event.button == widget.get!DraggableSettings.onButton)
		{
			event.handled = true;
			event.beginDrag = true;
		}
	}

	void onDrag(WidgetProxy widget, ref DragEvent event)
	{
		widget.get!WidgetTransform.relPos += event.delta;
	}
}

struct ScrollableAreaParts
{
	WidgetProxy scrollable;
	alias scrollable this;
	WidgetProxy canvas;
}

@Component("ScrollableData", Replication.none)
struct ScrollableData
{
	ivec2 contentOffset;
	ivec2 contentSize;
	ivec2 windowSize;
	bool isScrollbarNeeded() { return contentSize.y > windowSize.y; }
	ivec2 maxPos() { return vector_max(ivec2(0,0), contentSize - windowSize); }
	void clampPos() {
		contentOffset = vector_clamp(contentOffset, ivec2(0,0), maxPos);
	}
}

struct ScrollableArea
{
	static:
	ScrollableAreaParts create(WidgetProxy parent) {
		auto scrollable = parent.createChild(WidgetType("Scrollable"),
			ScrollableData(),
			WidgetEvents(&onScroll, &measure, &layout, &onSliderDrag)).setHLayout(0, padding4(0)).measuredSize(10, 10);
		auto container = scrollable.createChild(WidgetType("Container"), WidgetEvents(&clipDraw)).hvexpand;
		auto canvas = container.createChild(WidgetType("Canvas"));
		auto scrollbar = ScrollBarLogic.create(scrollable, scrollable/*receive drag event*/);
		scrollbar.vexpand;

		return ScrollableAreaParts(scrollable, canvas);
	}

	void onSliderDrag(WidgetProxy scrollable, ref ScrollBarEvent event)
	{
		auto data = scrollable.get!ScrollableData;
		if (event.maxPos)
			data.contentOffset.y = (event.pos * data.maxPos.y) / event.maxPos;
		else
			data.contentOffset.y = 0;
		//data.clampPos; unnesessary
	}

	void onScroll(WidgetProxy scrollable, ref ScrollEvent event)
	{
		if (event.sinking) return;
		auto data = scrollable.get!ScrollableData;
		data.contentOffset += ivec2(event.delta) * 50; // TODO settings
		data.clampPos;
		event.handled = true; // TODO do not handle if not scrolled, so higher scrolls will work
	}

	void clipDraw(WidgetProxy scrollable, ref DrawEvent event)
	{
		if (event.sinking) {
			auto transform = scrollable.getOrCreate!WidgetTransform;
			event.renderQueue.pushClipRect(irect(transform.absPos, transform.size));
		} else {
			event.renderQueue.popClipRect();
		}
	}

	void measure(WidgetProxy scrollable, ref MeasureEvent event)
	{
		// scrollable -> container -> canvas
		auto canvasTransform = scrollable.children[0].children[0].get!WidgetTransform;
		scrollable.get!ScrollableData.contentSize = canvasTransform.measuredSize;
	}

	void layout(WidgetProxy scrollable, ref LayoutEvent event)
	{
		auto data = scrollable.get!ScrollableData;
		auto rootTransform = scrollable.get!WidgetTransform;
		data.windowSize = rootTransform.size;
		data.clampPos;

		WidgetProxy cont = scrollable.children[0];
		auto contTran = cont.get!WidgetTransform;

		auto containerTransform = cont.get!WidgetTransform;
		containerTransform.minSize = ivec2(0, 0);
		containerTransform.measuredSize = ivec2(0, 0);

		auto canvasTransform = cont.children[0].get!WidgetTransform;
		auto scrollbar = scrollable.children[1];

		if (data.isScrollbarNeeded)
		{
			// set scrollbar
			scrollbar.remove!hidden;
			ScrollBarLogic.setPosSize(scrollable.children[1], data.contentOffset.y, data.contentSize.y, data.windowSize.y);
			canvasTransform.relPos.y = -data.contentOffset.y;
		}
		else
		{
			// no scrollbar
			scrollbar.set(hidden());
			canvasTransform.relPos.y = 0;
		}
	}
}

struct ScrollBarEvent
{
	int pos;
	int maxPos;
	mixin GuiEvent!();
}

struct ScrollBarParts
{
	WidgetProxy scrollbar;
	alias scrollbar this;
	WidgetProxy slider;
}

struct ScrollBarLogic
{
	static:
	ScrollBarParts create(WidgetProxy parent, WidgetId eventReceiver = WidgetId(0)) {
		auto scroll = parent.createChild(WidgetType("ScrollBar"))
			.vexpand.minSize(10, 20).addBackground(color_gray);
		auto slider = scroll.createChild(WidgetType("ScrollHandle"), WidgetReference(eventReceiver))
			.minSize(10, 10)
			.measuredSize(0, 100)
			.handlers(&onSliderDrag, &DraggableLogic.onPress)
			.addBackground(color_asbestos);
		return ScrollBarParts(scroll, slider);
	}

	void onSliderDrag(WidgetProxy slider, ref DragEvent event)
	{
		auto tr = slider.get!WidgetTransform;
		auto parent_tr = slider.ctx.get!WidgetTransform(tr.parent);
		int pos = slider.ctx.state.curPointerPos.y - slider.ctx.state.draggedWidgetOffset.y - parent_tr.absPos.y;
		int maxPos = parent_tr.size.y - tr.size.y;
		pos = clamp(pos, 0, maxPos);
		tr.relPos.y = pos;
		auto reference = slider.get!WidgetReference;
		if (reference.widgetId)
			slider.ctx.postEvent(reference.widgetId, ScrollBarEvent(pos, maxPos));
	}

	// Assumes clamped canvasPos
	void setPosSize(WidgetProxy scroll, int canvasPos, int canvasSize, int windowSize)
	{
		assert(canvasSize > windowSize);
		auto scrollTransform = scroll.get!WidgetTransform;
		auto sliderTransform = scroll.children[0].get!WidgetTransform;
		int scrollSize = windowSize;
		int sliderSize = (windowSize * scrollSize) / canvasSize;
		int sliderMaxPos = scrollSize - sliderSize;

		sliderTransform.relPos.y = canvasPos * sliderMaxPos / (canvasSize - windowSize);
		sliderTransform.size.y = sliderSize;
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

@Component("gui.LinearLayoutSettings", Replication.none)
struct LinearLayoutSettings
{
	int spacing; /// distance between items
	padding4 padding; /// borders around items
	Alignment alignment;

	// internal state
	int numExpandableChildren;
}

alias HLayout = LinearLayout!true;
alias VLayout = LinearLayout!false;

alias setHLayout = setLinearLayout!true;
alias setVLayout = setLinearLayout!false;

WidgetProxy setLinearLayout(bool hori)(WidgetProxy widget, int spacing, padding4 padding, Alignment alignTo = Alignment.min)
{
	LinearLayout!hori.attachTo(widget, spacing, padding, alignTo);
	return widget;
}

struct LinearLayout(bool horizontal)
{
	static:
	WidgetProxy create(WidgetProxy parent, int spacing, padding4 padding, Alignment alignTo = Alignment.min)
	{
		WidgetProxy layout = parent.createChild(WidgetType("LinearLayout"));
		attachTo(layout, spacing, padding, alignTo);
		return layout;
	}

	void attachTo(WidgetProxy widget, int spacing, padding4 padding, Alignment alignTo = Alignment.min)
	{
		//writefln("attachTo %s %s", widget.widgetType, widget.wid);
		widget.set(LinearLayoutSettings(spacing, padding, alignTo));
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

		static if (horizontal) int widthPad = settings.padding.vert;
		else int widthPad = settings.padding.hori;

		static if (horizontal) int lengthPad = settings.padding.hori;
		else int lengthPad = settings.padding.vert;

		int minRootWidth = maxChildWidth + widthPad;
		int minRootLength = childrenLength + cast(int)(children.length-1)*settings.spacing + lengthPad;
		auto transform = widget.get!WidgetTransform;
		transform.measuredSize = sizeFromWidthLength(minRootWidth, minRootLength);
	}

	void layout(WidgetProxy widget, ref LayoutEvent event)
	{
		auto settings = widget.get!LinearLayoutSettings;
		auto rootTransform = widget.get!WidgetTransform;

		static if (horizontal) int widthPad = settings.padding.vert;
		else int widthPad = settings.padding.hori;

		int maxChildWidth = width(rootTransform.size) - widthPad;

		int extraLength = length(rootTransform.size) - length(rootTransform.measuredSize);
		int extraPerWidget = settings.numExpandableChildren > 0 ? extraLength/settings.numExpandableChildren : 0;

		static if (horizontal) int topOffset = settings.padding.left;
		else int topOffset = settings.padding.top;
		static if (horizontal) int widthOffset = settings.padding.top;
		else int widthOffset = settings.padding.left;

		topOffset -= settings.spacing; // compensate extra spacing before first child

		foreach(child; widget.children)
		{
			topOffset += settings.spacing;
			auto childTransform = child.get!WidgetTransform;
			childTransform.relPos = sizeFromWidthLength(widthOffset, topOffset);

			ivec2 childSize = childTransform.constrainedSize;
			if (hasExpandableLength(child)) length(childSize) += extraPerWidget;
			if (hasExpandableWidth(child)) width(childSize) = maxChildWidth;
			else width(childTransform.relPos) += alignOnAxis(width(childSize), settings.alignment, maxChildWidth);
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


alias SinkT = void delegate(const(char)[]);
alias Formatter(Row) = void function(Row row, scope SinkT sink);

struct Column(Row)
{
	string name;
	int width;
	Formatter!Row formatter;
}

struct ListInfo(Row)
{
	ColumnInfo[] columnInfos;
	void function(Row row, scope SinkT sink)[] formatters;
}

ListInfo!Row parseListInfo(Row)()
{
	import std.traits;
	ListInfo!Row result;
	Row r;
	foreach(string memberName; __traits(allMembers, Row))
	{
		foreach(attr; __traits(getAttributes, __traits(getMember, r, memberName)))
		{
			static if (is(typeof(attr) == Column!Row))
			{
				result.columnInfos ~= ColumnInfo(attr.name, attr.width);
				result.formatters ~= attr.formatter;
			}
		}
	}
	return result;
}

class AutoListModel(Model) : ListModel
{
	alias Row = typeof(Model.init[0]);
	Model model;
	ListInfo!Row info = parseListInfo!Row;
	int selectedRow = -1;

	this(Model)(Model model)
	{
		this.model = model;
	}

	override int numLines() { return cast(int)model.length; }
	override int numColumns() { return cast(int)info.columnInfos.length; }
	override ref ColumnInfo columnInfo(int column) {
		return info.columnInfos[column];
	}
	override void getColumnText(int column, scope SinkT sink) {
		sink(info.columnInfos[column].name);
	}
	override void getCellText(int column, int row, scope SinkT sink) {
		info.formatters[column](model[row], sink);
	}
	override bool isLineSelected(int row) {
		return row == selectedRow;
	}
	override void onLineClick(int row) {
		selectedRow = row;
	}

	bool hasSelected() @property {
		return selectedRow < model.length && selectedRow >= 0;
	}
}

class ArrayListModel(Row) : AutoListModel!(Row[])
{
	this(Row[] rows) { super(rows); }
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
	WidgetProxy create(WidgetProxy parent, ListModel model)
	{
		WidgetProxy list = parent.createChild(
			ListData(model, parent.ctx.style.font),
			WidgetEvents(
				&drawWidget, &pointerMoved, &pointerPressed, &pointerReleased,
				&enterWidget, &leaveWidget, &clickWidget, &onScroll),
			WidgetStyle(baseColor),
			WidgetType("List"));
		return list;
	}

	void drawWidget(WidgetProxy widget, ref DrawEvent event)
	{
		if (event.bubbling) return;

		auto data = widget.get!ListData;
		auto transform = widget.getOrCreate!WidgetTransform;
		auto style = widget.get!WidgetStyle;

		irect transformRect = irect(transform.absPos, transform.size);

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

		int numVisibleLines = clamp(lastVisibleLine - firstVisibleLine + 1, 0, numLines);

		// for folding arrow positioning
		int charW = data.font.metrics.advanceX;

		bool isLineHovered(int line) { return data.hoveredLine == line; }

		void drawBackground()
		{
			int lineY = transform.absPos.y + headerHeight;
			foreach(visibleLine; 0..numVisibleLines)
			{
				int line = firstVisibleLine + visibleLine;
				auto color_selected = rgb(217, 235, 249);
				auto color_hovered = rgb(207, 225, 239);

				Color4ub color;
				if (isLineHovered(line)) color = color_hovered;
				else if (data.model.isLineSelected(line)) color = color_selected;
				else color = line % 2 ? rgb(255, 255, 255) : rgb(250, 250, 250); // color_white

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
			//params.monospaced = true;
			params.scissors = rectIntersection(irect(pos, size), transformRect);
			//params.scissors = irect(pos, size);
			params.meshText(data.model.columnInfo(column).name);
		}

		void drawCell(int column, int line, irect rect)
		{
			auto params = event.renderQueue.startTextAt(vec2(rect.position));
			params.font = data.font;
			params.color = color_wet_asphalt;
			params.depth = event.depth+2;
			//params.monospaced = true;
			params.scissors = rectIntersection(rect, transformRect);

			void sinkHandler(const(char)[] str) {
				params.meshText(str);
			}

			if (column == 0)
			{
				params.origin.x += charW * data.model.getLineIndent(line);
				final switch(data.model.getLineType(line))
				{
					case TreeLineType.leaf: params.meshText("  "); break;
					case TreeLineType.collapsedNode: params.meshText("► "); break;
					case TreeLineType.expandedNode: params.meshText("▼ "); break;
				}
			}

			data.model.getCellText(column, line, &sinkHandler);
			params.alignMeshedText(data.model.columnInfo(column).alignment, Alignment.min, rect.size);
		}

		event.renderQueue.pushClipRect(transformRect);
		drawBackground();

		int colX = transform.absPos.x;
		// columns
		foreach(column; 0..data.model.numColumns)
		{
			int colW = data.model.columnInfo(column).width;
			int cellW = colW - data.contentPadding.x*2;

			// separator
			ivec2 separatorStart = ivec2(colX + colW-1, transform.absPos.y);
			event.renderQueue.drawRectFill(vec2(separatorStart), vec2(1, transform.size.y), event.depth+3, color_silver);

			// clip
			event.renderQueue.pushClipRect(irect(colX+data.contentPadding.x, transform.absPos.y, cellW, transform.size.y));

			// header
			ivec2 headerPos  = ivec2(colX, transform.absPos.y) + data.headerPadding;
			ivec2 headerSize = ivec2(colW, headerHeight) - data.headerPadding*2;
			drawColumnHeader(column, headerPos, headerSize);
			int lineY = transform.absPos.y + headerHeight;

			// cells
			foreach(line; 0..numVisibleLines)
			{
				ivec2 cellPos = ivec2(colX, lineY);
				ivec2 cellSize = ivec2(colW, lineHeight);

				ivec2 cellContentPos = cellPos + data.contentPadding;
				ivec2 cellContentSize = cellSize - data.contentPadding*2;

				drawCell(column, firstVisibleLine+line, irect(cellContentPos, cellContentSize));
				lineY += lineHeight;
			}

			event.renderQueue.popClipRect();
			colX += colW;
		}
		event.renderQueue.popClipRect();

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
		widget.get!ListData.hoveredLine = -1;
	}

	void leaveWidget(WidgetProxy widget, ref PointerLeaveEvent event)
	{
		widget.get!ListData.hoveredLine = -1;
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
		else
		{
			data.model.onLineClick(-1);
		}
	}
}

/// Creates a frame that shows a tree of all widgets.
/// Highlights clicked widgets
WidgetProxy createGuiDebugger(WidgetProxy root)
{
	WidgetId highlightedWidget;

	// Tree widget
	struct TreeNode
	{
		WidgetId wid;
		TreeLineType nodeType;
		int indent;
		int numExpandedChildren;
	}

	class WidgetTreeModel : ListModel
	{
		import std.format : formattedWrite;
		import voxelman.container.gapbuffer;
		GapBuffer!TreeNode nodeList;
		WidgetProxy widgetAt(size_t i) { return WidgetProxy(nodeList[i].wid, root.ctx); }
		int selectedLine = -1;
		ColumnInfo[2] columnInfos = [ColumnInfo("Type", 200), ColumnInfo("Id", 50, Alignment.max)];

		void clear()
		{
			nodeList.clear();
			selectedLine = -1;
		}

		override int numLines() { return cast(int)nodeList.length; }
		override int numColumns() { return 2; }
		override ref ColumnInfo columnInfo(int column) {
			return columnInfos[column];
		}
		override void getColumnText(int column, scope void delegate(const(char)[]) sink) {
			if (column == 0) sink("Widget type");
			else if (column == 1) sink("Widget id");
			else assert(false);
		}
		override void getCellText(int column, int line, scope void delegate(const(char)[]) sink) {
			if (column == 0) sink(widgetAt(line).widgetType);
			else formattedWrite(sink, "%s", nodeList[line].wid);
		}
		override bool isLineSelected(int line) { return line == selectedLine; }
		override void onLineClick(int line) {
			selectedLine = line;
			if (selectedLine == -1)
				highlightedWidget = 0;
			else
				highlightedWidget = nodeList[line].wid;
		}
		override TreeLineType getLineType(int line) {
			return nodeList[line].nodeType;
		}
		override int getLineIndent(int line) { return nodeList[line].indent; }
		override void toggleLineFolding(int line) {
			if (nodeList[line].nodeType == TreeLineType.collapsedNode) expandWidget(line);
			else collapseWidget(line);
		}
		void expandWidget(int line)
		{
			//writefln("expand %s %s", line, nodeList[line].wid);
			auto container = root.ctx.get!WidgetContainer(nodeList[line].wid);
			if (container is null || container.children.length == 0) {
				nodeList[line].nodeType = TreeLineType.leaf;
				return;
			}
			auto insertPos = line+1;
			auto indent = nodeList[line].indent+1;
			foreach(wid; container.children)
			{
				TreeLineType nodeType = numberOfChildren(root.ctx, wid) ? TreeLineType.collapsedNode : TreeLineType.leaf;
				nodeList.putAt(insertPos++, TreeNode(wid, nodeType, indent));
			}
			nodeList[line].nodeType = TreeLineType.expandedNode;
		}
		void collapseWidget(int line)
		{
			//writefln("collapse %s", line, nodeList[line].wid);
			if (line+1 == nodeList.length) {
				nodeList[line].nodeType = TreeLineType.leaf;
				return;
			}

			auto parentIndent = nodeList[line].indent;
			size_t numItemsToRemove;
			foreach(node; nodeList[line+1..$])
			{
				if (node.indent <= parentIndent) break;
				++numItemsToRemove;
			}
			nodeList.remove(line+1, numItemsToRemove);
			nodeList[line].nodeType = TreeLineType.collapsedNode;
		}
	}

	void drawHighlight(WidgetProxy widget, ref DrawEvent event)
	{
		if (event.bubbling) return;

		// highlight widget
		auto t = widget.ctx.get!WidgetTransform(highlightedWidget);
		if (t)
		{
			event.renderQueue.pushClipRect(irect(ivec2(0,0), event.renderQueue.renderer.framebufferSize));
			event.renderQueue.drawRectLine(vec2(t.absPos), vec2(t.size), 10_000, Colors.red);
			event.renderQueue.popClipRect();
		}
	}

	auto model = new WidgetTreeModel;
	auto tree_frame = Frame.create(root);
	tree_frame.getOrCreate!WidgetEvents.addEventHandler(&drawHighlight);
	tree_frame.minSize(250, 400).pos(10, 10).makeDraggable.moveToTop;
	tree_frame.container.setVLayout(2, padding4(2));
	tree_frame.header.setHLayout(2, padding4(4), Alignment.center);
	tree_frame.header.createIcon("tree", ivec2(16, 16), Colors.black);
	tree_frame.header.createText("Widget tree");
	auto widget_tree = ColumnListLogic.create(tree_frame.container, model).minSize(250, 300).hvexpand;

	void refillTree()
	{
		model.clear;
		foreach(rootId; root.ctx.roots)
		{
			TreeLineType nodeType = numberOfChildren(root.ctx, rootId) ? TreeLineType.collapsedNode : TreeLineType.leaf;
			model.nodeList.put(TreeNode(rootId, nodeType));
		}
	}
	refillTree();
	createTextButton(tree_frame.container, "Refresh", &refillTree).hexpand;

	return tree_frame;
}
