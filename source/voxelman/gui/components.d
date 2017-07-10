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


/// Mandatory component
@Component("gui.WidgetTransform", Replication.none)
struct WidgetTransform
{
	ivec2 relPos; // set by user
	ivec2 size;   // set by user
	ivec2 absPos; // updated in layout phase

	WidgetId parent; // 0 in root widget

	ivec2 minSize; // updated in measure phase
	void delegate(WidgetId) measureHandler; // called in measure phase
	void delegate(WidgetId) layoutHandler;  // called in  layout phase
}

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

@Component("gui.WidgetContainer", Replication.none)
struct WidgetContainer
{
	WidgetId[] children;
	void put(WidgetId wId) {
		children ~= wId;
	}
}

void bringToFront(GuiContext ctx, WidgetId widget)
{
	auto parentId = ctx.widgets.get!WidgetTransform(widget).parent;

}

@Component("gui.WidgetRespondsToPointer", Replication.none)
struct WidgetRespondsToPointer {}

@Component("gui.WidgetIsFocusable", Replication.none)
struct WidgetIsFocusable {}

@Component("gui.WidgetEvents", Replication.none)
struct WidgetEvents
{
	this(Handlers...)(Handlers handlers)
	{
		addEventHandlers(handlers);
	}
	private alias EventHandler = bool delegate(WidgetId widgetId, ref void* event);

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

	void addEventHandler(EventType)(void delegate(WidgetId, ref EventType) handler)
	{
		eventHandlers[typeid(EventType)] ~= cast(EventHandler)handler;
	}

	void addEventHandler(EventType)(void function(WidgetId, ref EventType) handler)
	{
		// We use non-null value because null if a valid context pointer in delegates
		DelegatePayload fakeDelegate = {FUNCTION_CONTEXT_VALUE, handler};
		eventHandlers[typeid(EventType)] ~= *cast(EventHandler*)&fakeDelegate;
	}

	void removeEventHandlers(T)()
	{
		eventHandlers.remove(typeid(T));
	}

	/// Returns true if event was handled
	/// This handler will be called by Gui twice, before and after visiting its children.
	/// In first case sinking flag will be true;
	void postEvent(Event)(WidgetId widgetId, auto ref Event event)
	{
		foreach(handler; eventHandlers.get(typeid(Event), null))
		{
			auto payload = *cast(DelegatePayload*)&handler;
			if (payload.contextPtr == FUNCTION_CONTEXT_VALUE)
				(cast(void function(WidgetId, ref Event))payload.funcPtr)(widgetId, event);
			else
				(cast(void delegate(WidgetId, ref Event))handler)(widgetId, event);
		}
	}
}
