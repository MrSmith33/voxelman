/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.gui.components;

import voxelman.math;
import voxelman.gui;
import cbor : ignore;
import voxelman.graphics : Color4ub;
import datadriven.entityman : EntityManager;

void registerComponents(ref EntityManager widgets)
{
	widgets.registerComponent!WidgetTransform;
	widgets.registerComponent!WidgetStyle;
	widgets.registerComponent!WidgetName;
	widgets.registerComponent!WidgetType;
	widgets.registerComponent!WidgetContainer;
	widgets.registerComponent!WidgetRespondsToPointer;
	widgets.registerComponent!WidgetIsFocusable;
	widgets.registerComponent!WidgetEvents;
}

enum WidgetFlags
{
	hexpand = 0b0000_0001,
	vexpand = 0b0000_0010,
}

/// Mandatory component
@Component("gui.WidgetTransform", Replication.none)
struct WidgetTransform
{
	ivec2 relPos; // set by user/layout
	ivec2 size;   // set by user/layout
	ivec2 minSize;// set by user
	WidgetId parent; // 0 in root widget

	uint flags; // flags from WidgetFlags
	ivec2 absPos; // updated in layout phase from root to leaves by parent layout
	ivec2 measuredSize; // updated in measure phase from leaves to root by widget's layout
	ivec2 constrainedSize() { return vector_max(measuredSize, minSize); }
	bool hasHexpand() { return !!(flags & WidgetFlags.hexpand); }
	bool hasVexpand() { return !!(flags & WidgetFlags.vexpand); }
	void hexpand(bool val) { flags = set_flag(flags, val, WidgetFlags.hexpand); }
	void vexpand(bool val) { flags = set_flag(flags, val, WidgetFlags.vexpand); }
	void hvexpand(bool val) { hexpand(val); vexpand(val); }
}

/// Convenience setters
WidgetProxy minSize(WidgetProxy widget, ivec2 minSize) { widget.getOrCreate!WidgetTransform.minSize = minSize; return widget; } /// ditto
WidgetProxy minSize(WidgetProxy widget, int w, int h) { widget.getOrCreate!WidgetTransform.minSize = ivec2(w, h); return widget; } /// ditto
WidgetProxy size(WidgetProxy widget, int w, int h) { widget.getOrCreate!WidgetTransform.size = ivec2(w, h); return widget; } /// ditto
WidgetProxy pos(WidgetProxy widget, int x, int y) { widget.getOrCreate!WidgetTransform.relPos = ivec2(x, y); return widget; } /// ditto
WidgetProxy hexpand(WidgetProxy widget) { widget.getOrCreate!WidgetTransform.hexpand = true; return widget; } /// ditto
WidgetProxy vexpand(WidgetProxy widget) { widget.getOrCreate!WidgetTransform.vexpand = true; return widget; } /// ditto
WidgetProxy hvexpand(WidgetProxy widget) { widget.getOrCreate!WidgetTransform.hvexpand = true; return widget; } /// ditto
WidgetProxy measuredSize(WidgetProxy widget, ivec2 ms) { widget.getOrCreate!WidgetTransform.measuredSize = ms; return widget; } /// ditto

bool hasHexpand(WidgetProxy widget) { return widget.getOrCreate!WidgetTransform.hasHexpand; } /// ditto
bool hasVexpand(WidgetProxy widget) { return widget.getOrCreate!WidgetTransform.hasVexpand; } /// ditto

@Component("gui.WidgetStyle", Replication.none)
struct WidgetStyle
{
	Color4ub color;
}

@Component("gui.WidgetName", Replication.none)
struct WidgetName
{
	string name;
}

@Component("gui.WidgetType", Replication.none)
struct WidgetType
{
	string name;
}

string widgetType(WidgetProxy widget) {
	if (auto type = widget.get!WidgetType) return type.name;
	return "Widget";
}

string widgetType(GuiContext ctx, WidgetId wid) {
	if (auto type = ctx.widgets.get!WidgetType(wid)) return type.name;
	return "Widget";
}

@Component("gui.WidgetContainer", Replication.none)
struct WidgetContainer
{
	WidgetId[] children;
	void put(WidgetId wId) {
		children ~= wId;
	}
	void bringToFront(WidgetId wid) {
		foreach(index, child; children)
		{
			if (child == wid)
			{
				moveItemToEnd(index, children);
				return;
			}
		}
	}
}

///
ChildrenRange children(WidgetProxy w) {
	if (auto container = w.ctx.widgets.get!WidgetContainer(w.wid)) return ChildrenRange(w.ctx, container.children);
	return ChildrenRange(w.ctx, null);
}

void moveItemToEnd(T)(size_t index, T[] array)
{
	if (index+1 < array.length) // dont use length-1 due to size_t underflow
	{
		T item = array[index];
		foreach(i; index..array.length-1)
		{
			array[i] = array[i+1];
		}
		array[$-1] = item;
	}
}

unittest
{
	void test(T)(size_t index, T[] array, T[] expected) {
		auto initial = array.dup;
		moveItemToEnd(index, array);
		import std.string : format;
		assert(array == expected, format(
			"for (%s, %s) expected %s, got %s",
			index, initial, expected, array));
	}
	test(0, cast(int[])[], cast(int[])[]);
	test(0, [3], [3]);
	test(0, [3,2], [2,3]);
	test(0, [3,2,1], [2,1,3]);
	test(1, [3], [3]);
	test(1, [3,2], [3,2]);
	test(2, [3,2,1], [3,2,1]);
}

size_t numberOfChildren(WidgetProxy widget)
{
	if (auto container = widget.get!WidgetContainer) return container.children.length;
	return 0;
}

size_t numberOfChildren(GuiContext ctx, WidgetId wid)
{
	if (auto container = ctx.widgets.get!WidgetContainer(wid)) return container.children.length;
	return 0;
}

void bringToFront(WidgetProxy widget)
{
	auto parentId = widget.get!WidgetTransform.parent;
	if (auto container = widget.ctx.get!WidgetContainer(parentId))
		container.bringToFront(widget.wid);
}

@Component("gui.WidgetRespondsToPointer", Replication.none)
struct WidgetRespondsToPointer {}

@Component("gui.WidgetIsFocusable", Replication.none)
struct WidgetIsFocusable {}

@Component("gui.WidgetEvents", Replication.none)
struct WidgetEvents
{
	import std.stdio;
	this(Handlers...)(Handlers handlers)
	{
		addEventHandlers(handlers);
	}
	private alias EventHandler = void delegate(WidgetProxy widget, ref void* event);

	@ignore EventHandler[][TypeInfo] eventHandlers;

	void addEventHandlers(Handlers...)(Handlers handlers)
	{
		foreach(h; handlers) addEventHandler(h);
	}

	private enum void* FUNCTION_CONTEXT_VALUE = cast(void*)42;
	private static struct DelegatePayload
	{
		void* contextPtr;
		void* funcPtr;
	}

	void addEventHandler(EventType)(void delegate(WidgetProxy, ref EventType) handler)
	{
		eventHandlers[typeid(EventType)] ~= cast(EventHandler)handler;
	}

	void addEventHandler(EventType)(void function(WidgetProxy, ref EventType) handler)
	{
		// We use non-null value because null if a valid context pointer in delegates
		DelegatePayload fakeDelegate = {FUNCTION_CONTEXT_VALUE, handler};
		eventHandlers[typeid(EventType)] ~= *cast(EventHandler*)&fakeDelegate;
	}

	void replaceEventHandler(EventType)(void delegate(WidgetProxy, ref EventType) handler)
	{
		eventHandlers[typeid(EventType)] = [cast(EventHandler)handler];
	}

	void replaceEventHandler(EventType)(void function(WidgetProxy, ref EventType) handler)
	{
		// We use non-null value because null if a valid context pointer in delegates
		DelegatePayload fakeDelegate = {FUNCTION_CONTEXT_VALUE, handler};
		eventHandlers[typeid(EventType)] = [*cast(EventHandler*)&fakeDelegate];
	}

	void removeEventHandlers(T)()
	{
		eventHandlers.remove(typeid(T));
	}

	/// Returns true if any handlers were called
	/// This handler will be called by Gui twice, before and after visiting its children.
	/// In first case sinking flag will be true;
	bool postEvent(Event)(WidgetProxy widget, auto ref Event event)
	{
		if (auto handlers = typeid(Event) in eventHandlers)
		{
			foreach(handler; *handlers)
			{
				auto payload = *cast(DelegatePayload*)&handler;
				if (payload.contextPtr == FUNCTION_CONTEXT_VALUE)
					(cast(void function(WidgetProxy, ref Event))payload.funcPtr)(widget, event);
				else
					(cast(void delegate(WidgetProxy, ref Event))handler)(widget, event);
			}
			return true;
		}
		else
			return false;
	}
}
