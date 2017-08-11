/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.gui.guicontext;

import std.stdio;
import datadriven;
import voxelman.graphics;
import voxelman.gui;
import voxelman.platform.input;
import voxelman.math;
import voxelman.text.linebuffer;
public import voxelman.platform.cursoricon : CursorIcon;

struct GuiState
{
	WidgetId draggingWidget;    /// Will receive onDrag events
	WidgetId focusedWidget;     /// Will receive all key events if input is not grabbed by other widget
	WidgetId hoveredWidget;     /// Widget over which pointer is located
	WidgetId inputOwnerWidget;  /// If set, this widget will receive all pointer movement events
	WidgetId lastClickedWidget; /// Used for double-click checking. Is set before click event distribution
	WidgetId pressedWidget;

	ivec2 canvasSize;
	ivec2 prevPointerPos = ivec2(int.max, int.max);
	ivec2 curPointerPos;
	/// Icon is reset after widget leave event and before widget enter event.
	/// If widget wants to change icon, it must set cursorIcon in PointerEnterEvent handler.
	CursorIcon cursorIcon;

	string delegate() getClipboard;
	void delegate(string) setClipboard;
}

class GuiContext
{
	EntityIdManager widgetIds;
	EntityManager widgets;
	WidgetId[string] nameToId;

	WidgetId[] roots;

	GuiState state;
	LineBuffer* debugText;

	this(LineBuffer* debugText)
	{
		widgets.eidMan = &widgetIds;
		widgets.registerComponent!WidgetContainer;
		widgets.registerComponent!WidgetEvents;
		widgets.registerComponent!WidgetTransform;
		widgets.registerComponent!WidgetIsFocusable;
		widgets.registerComponent!WidgetName;
		widgets.registerComponent!WidgetRespondsToPointer;
		widgets.registerComponent!WidgetStyle;

		roots ~= createWidget("root");
		this.debugText = debugText;
	}

	// SET, GET, HAS proxies
	void set(Components...)(WidgetId wid, Components components) { widgets.set(wid, components); }
	C* get(C)(WidgetId wid) { return widgets.get!C(wid); }
	C* getOrCreate(C)(WidgetId wid, C defVal = C.init) { return widgets.getOrCreate!C(wid, defVal); }
	bool has(C)(WidgetId wid) { return widgets.has!C(wid); }
	void remove(C)(WidgetId wid) { widgets.remove!C(wid); }

	// WIDGET METHODS

	/// returns 0 if not found
	WidgetId getByName(string name)
	{
		return nameToId.get(name, WidgetId(0));
	}

	/// Pass string as first parameter to set name
	/// Pass WidgetId as first parameter, or after string to set parent
	/// createWidget([string name,] [WidgetId parent,] Component... components)
	WidgetProxy createWidget(Components...)(Components components)
	{
		auto wId = widgetIds.nextEntityId();

		static if (is(Components[0] == string))
		{
			nameToId[components[0]] = wId;
			widgets.set(wId, WidgetName(components[0]));

			static if (is(Components[1] == WidgetId))
			{
				addChild(components[1], wId);
				enum firstComponent = 2;
			}
			else static if (is(Components[1] == WidgetProxy))
			{
				addChild(components[1].wid, wId);
				enum firstComponent = 2;
			}
			else
			{
				enum firstComponent = 1;
			}
		}
		else static if (is(Components[0] == WidgetId))
		{
			addChild(components[0], wId);
			enum firstComponent = 1;
		}
		else static if (is(Components[0] == WidgetProxy))
		{
			addChild(components[0].wid, wId);
			enum firstComponent = 1;
		}
		else
		{
			enum firstComponent = 0;
		}

		widgets.set(wId, components[firstComponent..$]);

		return WidgetProxy(wId, this);
	}

	void addChild(WidgetId parent, WidgetId child)
	{
		widgets.getOrCreate!WidgetContainer(parent).put(child);
		widgets.getOrCreate!WidgetTransform(child).parent = parent;
	}

	WidgetId[] widgetChildren(WidgetId wId)
	{
		if (auto container = widgets.get!WidgetContainer(wId)) return container.children;
		return null;
	}

	static struct WidgetTreeVisitor(bool rootFirst)
	{
		WidgetId root;
		GuiContext ctx;
		int opApply(scope int delegate(WidgetId) del)
		{
			int visitSubtree(WidgetId root)
			{
				static if (rootFirst) {
					if (auto ret = del(root)) return ret;
				}
				foreach(child; ctx.widgetChildren(root))
					if (auto ret = visitSubtree(child))
						return ret;
				static if (!rootFirst) {
					if (auto ret = del(root)) return ret;
				}
				return 0;
			}

			return visitSubtree(root);
		}
	}

	auto visitWidgetTreeRootFirst(WidgetId root)
	{
		return WidgetTreeVisitor!true(root, this);
	}

	auto visitWidgetTreeChildrenFirst(WidgetId root)
	{
		return WidgetTreeVisitor!false(root, this);
	}

	bool postEvent(Event)(WidgetId wId, auto ref Event event)
	{
		event.ctx = this;
		if (auto events = widgets.get!WidgetEvents(wId)) return events.postEvent(wId, event);
		return false;
	}

	static bool containsPointer(WidgetId widget, GuiContext context, ivec2 pointerPos)
	{
		auto transform = context.widgets.getOrCreate!WidgetTransform(widget);
		return irect(transform.absPos, transform.size).contains(pointerPos);
	}


	// EVENT HANDLERS

	void onScroll(dvec2 delta)
	{
		auto event = ScrollEvent(vec2(-delta));

		foreach_reverse(root; roots)
		{
			WidgetId[] path = buildPathToLeaf!(containsPointer)(this, root, this, state.curPointerPos);
			WidgetId[] eventConsumerChain = propagateEventSinkBubble(this, path, event, OnHandle.StopTraversing);
		}
	}

	void onKeyPress(KeyCode key, uint modifiers)
	{
		if (focusedWidget)
		{
			auto event = KeyPressEvent(key, modifiers);
			postEvent(focusedWidget, event);
		}
	}

	void onKeyRelease(KeyCode key, uint modifiers)
	{
		if (focusedWidget)
		{
			auto event = KeyReleaseEvent(key, modifiers);
			postEvent(focusedWidget, event);
		}
	}

	void onCharEnter(dchar character)
	{
		if (focusedWidget)
		{
			auto event = CharEnterEvent(character);
			postEvent(focusedWidget, event);
		}
	}

	void pointerPressed(PointerButton button, uint modifiers)
	{
		auto event = PointerPressEvent(state.curPointerPos, button, modifiers);

		foreach_reverse(root; roots)
		{
			WidgetId[] path = buildPathToLeaf!(containsPointer)(this, root, this, state.curPointerPos);
			WidgetId[] eventConsumerChain = propagateEventSinkBubble(this, path, event, OnHandle.StopTraversing);

			if (eventConsumerChain.length > 0)
			{
				WidgetId consumer = eventConsumerChain[$-1];
				if (widgets.has!WidgetIsFocusable(consumer))
					focusedWidget = consumer;

				pressedWidget = consumer;
				return;
			}
		}

		focusedWidget = WidgetId(0);
	}

	void pointerReleased(PointerButton button, uint modifiers)
	{
		auto event = PointerReleaseEvent(state.curPointerPos, button, modifiers);

		foreach_reverse(root; roots)
		{
			WidgetId[] path = buildPathToLeaf!(containsPointer)(this, root, this, state.curPointerPos);

			foreach_reverse(item; path) // test if pointer over pressed widget.
			{
				if (item == pressedWidget)
				{
					WidgetId[] eventConsumerChain = propagateEventSinkBubble(this, path, event, OnHandle.StopTraversing);

					if (eventConsumerChain.length > 0)
					{
						if (pressedWidget == eventConsumerChain[$-1])
						{
							auto clickEvent = PointerClickEvent(state.curPointerPos, button);
							lastClickedWidget = pressedWidget;
							postEvent(pressedWidget, clickEvent);
						}
					}

					pressedWidget = WidgetId(0);
					return;
				}
			}
		}

		if (pressedWidget) // no one handled event. Let's pressed widget know that pointer was released.
		{
			postEvent(pressedWidget, event); // pressed widget will know if pointer was unpressed somewhere else.
			updateHovered(state.curPointerPos); // So widget knows if pointer released not over it.
		}

		pressedWidget = WidgetId(0);
	}

	void pointerMoved(ivec2 newPointerPos)
	{
		if (newPointerPos == state.curPointerPos) return;

		ivec2 delta = newPointerPos - state.prevPointerPos;
		state.prevPointerPos = state.curPointerPos;
		state.curPointerPos = newPointerPos;

		auto event = PointerMoveEvent(newPointerPos, delta);

		if (pressedWidget)
		{
			if (containsPointer(pressedWidget, this, state.curPointerPos))
			{
				postEvent(pressedWidget, event);
				if (event.handled)
				{
					hoveredWidget = pressedWidget;
					return;
				}
			}
		}
		else
		{
			if (updateHovered(newPointerPos))
			{
				postEvent(hoveredWidget, event);
				return;
			}
		}

		hoveredWidget = WidgetId(0);
	}

	private bool updateHovered(ivec2 pointerPos)
	{
		foreach_reverse(root; roots)
		{
			WidgetId[] path = buildPathToLeaf!(containsPointer)(this, root, this, pointerPos);
			foreach_reverse(widget; path)
			{
				if (widgets.has!WidgetRespondsToPointer(widget))
				{
					hoveredWidget = widget;
					return true;
				}
			}
		}

		hoveredWidget = WidgetId(0);
		return false;
	}

	void update(double deltaTime, RenderQueue renderQueue)
	{
		updateLayout();
		foreach(root; roots)
		{
			propagateEventSinkBubbleTree(this, root, GuiUpdateEvent(deltaTime));
			propagateEventSinkBubbleTree(this, root, DrawEvent(renderQueue));
		}
	}

	private void updateLayout()
	{
		foreach(root; roots)
		{
			widgets.getOrCreate!WidgetTransform(root).size = state.canvasSize;

			MeasureEvent measureEvent;
			foreach(wid; visitWidgetTreeChildrenFirst(root))
			{
				bool hasHandlers = postEvent(wid, measureEvent);
				if (!hasHandlers) absoluteMeasureHandler(wid);
			}

			LayoutEvent layoutEvent;
			foreach(wid; visitWidgetTreeRootFirst(root))
			{
				bool hasHandlers = postEvent(wid, layoutEvent);
				if (!hasHandlers) absoluteLayoutHandler(wid);
			}
		}
	}

	void absoluteMeasureHandler(WidgetId wid)
	{
		auto transform = widgets.getOrCreate!WidgetTransform(wid);
		foreach (WidgetId childId; widgetChildren(wid))
		{
			auto childTransform = widgets.getOrCreate!WidgetTransform(childId);
			childTransform.applyConstraints();
		}
	}

	void absoluteLayoutHandler(WidgetId wid)
	{
		auto parentTransform = widgets.getOrCreate!WidgetTransform(wid);
		foreach (WidgetId childId; widgetChildren(wid))
		{
			auto childTransform = widgets.getOrCreate!WidgetTransform(childId);
			childTransform.absPos = parentTransform.absPos + childTransform.relPos;
			childTransform.size = childTransform.measuredSize;
		}
	}

	// STATE

	string clipboard()
	{
		return state.getClipboard();
	}

	void clipboard(S)(S str)
	{
		import std.array : array;
		state.setClipboard(str.byChar.array);
	}

	void cursorIcon(CursorIcon icon) { state.cursorIcon = icon; }

	WidgetId draggingWidget() { return state.draggingWidget; }
	void draggingWidget(WidgetId wId) { state.draggingWidget = wId; }

	WidgetId focusedWidget() { return state.focusedWidget; }
	void focusedWidget(WidgetId wId)
	{
		if (state.focusedWidget != wId)
		{
			if (state.focusedWidget) postEvent(state.focusedWidget, FocusLoseEvent());
			if (wId) postEvent(wId, FocusGainEvent());
			state.focusedWidget = wId;
		}
	}

	WidgetId hoveredWidget() { return state.hoveredWidget; }
	void hoveredWidget(WidgetId wId) @trusted
	{
		if (state.hoveredWidget != wId)
		{
			if (state.hoveredWidget) postEvent(state.hoveredWidget, PointerLeaveEvent());
			cursorIcon = CursorIcon.arrow;
			if (wId) postEvent(wId, PointerEnterEvent());
			state.hoveredWidget = wId;
		}
	}

	WidgetId inputOwnerWidget() { return state.inputOwnerWidget; }
	void inputOwnerWidget(WidgetId wId) { state.inputOwnerWidget = wId; }

	WidgetId lastClickedWidget() { return state.lastClickedWidget; }
	void lastClickedWidget(WidgetId wId) { state.lastClickedWidget = wId; }

	WidgetId pressedWidget() { return state.pressedWidget; }
	void pressedWidget(WidgetId wId) { state.pressedWidget = wId; }

	// HANDLERS
	bool handleWidgetUpdate(WidgetId wId, ref GuiUpdateEvent event)
	{
		return true;
	}
}
