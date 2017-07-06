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
	ivec2 relPos;
	ivec2 size;
	ivec2 absPos;

	WidgetId parent;
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

	void addEventHandler(T)(T handler)
	{
		import std.traits : ParameterTypeTuple, isDelegate;
		static assert(isDelegate!T, "handler must be a delegate, not " ~ T.stringof);
		alias Params = ParameterTypeTuple!T;
		static assert(is(Params[0] == WidgetId), "handler must accept Widget as first parameter");
		static assert(Params.length == 2, "handler must have only two parameters, Widget and Event");
		eventHandlers[typeid(Params[1])] ~= cast(EventHandler)handler;
	}

	void removeEventHandlers(T)()
	{
		eventHandlers.remove(typeid(T));
	}

	/// Returns true if event was handled
	/// This handler will be called by Gui twice, before and after visiting its children.
	/// In first case sinking flag will be true;
	bool postEvent(Event)(WidgetId widgetId, auto ref Event event)
	{
		bool result = false;
		foreach(handler; eventHandlers.get(typeid(Event), null))
		{
			result |= (cast(bool delegate(WidgetId, ref Event))handler)(widgetId, event);
		}
		return result;
	}
}
