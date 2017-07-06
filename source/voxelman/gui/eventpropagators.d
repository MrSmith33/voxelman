/**
Copyright: Copyright (c) 2013-2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.gui.eventpropagators;

import std.traits;
import voxelman.gui;

///
enum PropagatingStrategy
{
	/// First visits parent then child until target is reached.
	/// Then sets event's bubbling flag to true and visits widgets from
	/// target to root.
	SinkBubble,

	/// First visits target then its parent etc, until reaches root.
	/// Then sets event's sinking flag to true and visits widgets from root to target.
	BubbleSink,

	/// Visit all the subtree from bottom up. parent gets visited after all its children was visited.
	/// Also called Pre-order.
	ChildrenFirst,

	/// Visits all subtree from root to leafs, visiting parent first and then all its subtrees. Depth-first.
	/// Also called Post-order.
	ParentFirst
}

enum OnHandle
{
	StopTraversing,
	ContinueTraversing
}

/// Returns sub-chain that handled event if onHandle is StopTraversing
WidgetId[] propagateEventSinkBubble(Event)(
	GuiContext context,
	return WidgetId[] widgets,
	auto ref Event event,
	OnHandle onHandle = OnHandle.StopTraversing)
{
	// Phase 1: event sinking to target.
	event.sinking = true;

	foreach(index, widgetId; widgets)
	{
		event.handled = event.handled || context.postEvent(widgetId, event);

		if(onHandle == OnHandle.StopTraversing)
		{
			if (event.handled) return widgets[0..index+1];
		}
	}

	// Phase 2: event bubling from target.
	event.bubbling = true;
	foreach_reverse(index, widgetId; widgets)
	{
		event.handled = event.handled || context.postEvent(widgetId, event);

		if(onHandle == OnHandle.StopTraversing)
		{
			if (event.handled) return widgets[0..index+1];
		}
	}

	return null;
}

void propagateEventParentFirst(Event)(GuiContext context, WidgetId root, auto ref Event event)
{
	event.sinking = true;

	void propagateEvent(WidgetId root)
	{
		context.postEvent(root, event);

		foreach(WidgetId child; context.widgetChildren(root))
		{
			propagateEvent(child);
		}
	}

	propagateEvent(root);
}

void propagateEventSinkBubbleTree(Event)(GuiContext context, WidgetId root, auto ref Event event)
{
	event.sinking = true;
	context.postEvent(root, event);

	foreach (WidgetId widgetId; context.widgetChildren(root))
	{
		event.sinking = true;
		propagateEventSinkBubbleTree(context, widgetId, event);
	}

	event.bubbling = true;
	context.postEvent(root, event);
}

void propagateEventChildrenFirst(Event)(GuiContext context, WidgetId root, auto ref Event event)
{
	event.bubbling = true;

	void propagateEvent(WidgetId root)
	{
		foreach(child; context.widgetChildren(root)) propagateEvent(child);
		context.postEvent(root, event);
	}

	propagateEvent(root);
}

/// Tests all root's children with pred.
/// Then calls itself with found child.
/// Adds widgets satisfying pred to returned array.
/// Root widget is added first.
/// Can be used to find widget that is under cursor
/// Parameters:
///   pred function like bool fun(WidgetId widget, ...)
///   root root of widget subtree/tree
WidgetId[] buildPathToLeaf(alias pred, T...)(GuiContext context, WidgetId root, T data)
{
	WidgetId[] path;

	bool traverse(WidgetId root)
	{
		if(!pred(root, data)) return false;

		path ~= root;

		foreach(child; context.widgetChildren(root))
		{
			if (traverse(child))
			{
				return true;
			}
		}

		return true;
	}

	traverse(root);

	return path;
}
