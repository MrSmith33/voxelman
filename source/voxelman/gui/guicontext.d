/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.gui.guicontext;

import std.stdio;
import std.typecons : Flag, Yes, No;
import datadriven;
import voxelman.graphics;
import voxelman.gui;
import voxelman.platform.input;
import voxelman.math;
import voxelman.text.linebuffer;
public import voxelman.platform.cursoricon : CursorIcon;
import voxelman.gui.textedit.texteditorview;

struct GuiState
{
	WidgetId draggedWidget;    /// Will receive onDrag events
	WidgetId focusedWidget;     /// Will receive all key events if input is not grabbed by other widget
	WidgetId hoveredWidget;     /// Widget over which pointer is located
	WidgetId inputOwnerWidget;  /// If set, this widget will receive all pointer movement events
	WidgetId lastClickedWidget; /// Used for double-click checking. Is set before click event distribution
	WidgetId pressedWidget;

	ivec2 canvasSize;
	ivec2 prevPointerPos = ivec2(int.max, int.max);
	ivec2 pointerPressPos = ivec2(int.max, int.max);
	ivec2 curPointerPos;

	/// filled with curPointerPos - draggedWidget.absPos at the moment of press
	ivec2 draggedWidgetOffset;

	/// Icon is reset after widget leave event and before widget enter event.
	/// If widget wants to change icon, it must set cursorIcon in PointerEnterEvent handler.
	CursorIcon cursorIcon;

	string delegate() getClipboard;
	void delegate(string) setClipboard;
}

struct ImplicitGuiStyle
{
	import voxelman.container.chunkedbuffer;
	FontRef defaultFont;
	ChunkedBuffer!(FontRef, 16) fontStack;

	FontRef font() {
		if (fontStack.length) return fontStack.top;
		return defaultFont;
	}
	void pushFont(FontRef font) { fontStack.push(font); }
	void popFont() { fontStack.pop(); }

	SpriteRef iconPlaceholder;
	SpriteRef[string] iconMap;

	SpriteRef icon(string iconId) { return iconMap.get(iconId, iconPlaceholder); }
}

class GuiContext
{
	EntityIdManager widgetIds;
	EntityManager widgets;
	WidgetId[string] nameToId;

	/// Roots are auto-expanded on hvexpand to state.canvasSize
	WidgetId[] roots;

	GuiState state;
	ImplicitGuiStyle style;
	LineBuffer* debugText;

	this(LineBuffer* debugText)
	{
		widgets.eidMan = &widgetIds;
		voxelman.gui.widgets.registerComponents(widgets);
		voxelman.gui.components.registerComponents(widgets);
		voxelman.gui.textedit.texteditorview.registerComponents(widgets);

		roots ~= createWidget(WidgetType("root")).hvexpand;
		roots ~= createWidget(WidgetType("windows")).hvexpand;
		this.debugText = debugText;
	}

	WidgetProxy getRoot(size_t rootIndex) { return WidgetProxy(roots[rootIndex], this); }
	// context menus, drop-down lists, tooltips
	WidgetProxy createOverlay() {
		roots ~= createWidget(WidgetType("overlay")).hvexpand;
		return WidgetProxy(roots[$-1], this);
	}

	ChildrenRange getRoots() { return ChildrenRange(this, roots); }

	// layer for dropdown items, context menus and hints

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
		if (components.length > 0 &&
			!is(Components[0] == string) &&
			!is(Components[0] == WidgetProxy) &&
			!is(Components[0] == WidgetId))
	{
		auto wid = widgetIds.nextEntityId();
		widgets.set(wid, components);
		return WidgetProxy(wid, this);
	}

	/// ditto
	WidgetProxy createWidget(Components...)(string name, Components components)
	{
		auto wid = widgetIds.nextEntityId();
		nameToId[name] = wid;
		widgets.set(wid, WidgetName(name), components);
		return WidgetProxy(wid, this);
	}

	/// ditto
	WidgetProxy createWidget(Components...)(WidgetId parent, Components components)
	{
		auto wid = widgetIds.nextEntityId();
		widgets.set(wid, components);
		addChild(parent, wid);
		return WidgetProxy(wid, this);
	}

	/// ditto
	WidgetProxy createWidget(Components...)(string name, WidgetId parent, Components components)
	{
		auto wid = widgetIds.nextEntityId();
		nameToId[name] = wid;
		widgets.set(wid, WidgetName(name), components);
		addChild(parent, wid);
		return WidgetProxy(wid, this);
	}

	void removeWidget(WidgetId wid)
	{
		auto tr = widgets.getOrCreate!WidgetTransform(wid);

		foreach(widget; visitTreeChildrenFirstAll(wid))
			widgets.remove(wid);

		if (tr.parent)
		{
			auto container = widgets.get!WidgetContainer(tr.parent);
			if (container) container.removeChild(wid);
		}
		else // check if root
		{
			import std.algorithm : remove, countUntil;
			auto index = countUntil(roots, wid);
			if (index != -1) roots = remove(roots, index);
		}
	}

	/// Call to set parent after components are set
	/// because it will create WidgetTransform component for child
	/// which will be overwritten by set call if Components list
	/// contains WidgetTransform components too.
	void addChild(WidgetId parent, WidgetId child)
	{
		widgets.getOrCreate!WidgetContainer(parent).put(child);
		widgets.getOrCreate!WidgetTransform(child).parent = parent;
	}

	WidgetId[] widgetChildren(WidgetId wid)
	{
		if (auto container = widgets.get!WidgetContainer(wid)) return container.children;
		return null;
	}

	static struct WidgetTreeVisitor(bool rootFirst, bool onlyVisible)
	{
		WidgetId root;
		GuiContext ctx;
		int opApply(scope int delegate(WidgetProxy) del)
		{
			int visitSubtree(WidgetId root)
			{
				static if (rootFirst) {
					if (auto ret = del(WidgetProxy(root, ctx))) return ret;
				}

				foreach(child; ctx.widgetChildren(root))
				{
					static if (onlyVisible) {
						if (ctx.widgets.has!hidden(child)) continue;
					}
					if (auto ret = visitSubtree(child))
						return ret;
				}

				static if (!rootFirst) {
					if (auto ret = del(WidgetProxy(root, ctx))) return ret;
				}

				return 0;
			}

			return visitSubtree(root);
		}
	}

	auto visitTreeRootFirstVisible(WidgetId root) { return WidgetTreeVisitor!(true, true)(root, this); }
	auto visitTreeChildrenFirstVisible(WidgetId root) { return WidgetTreeVisitor!(false, true)(root, this); }
	auto visitTreeRootFirstAll(WidgetId root) { return WidgetTreeVisitor!(true, false)(root, this); }
	auto visitTreeChildrenFirstAll(WidgetId root) { return WidgetTreeVisitor!(false, false)(root, this); }

	bool postEvent(Event)(WidgetId wid, auto ref Event event)
	{
		if (auto events = widgets.get!WidgetEvents(wid))
			return events.postEvent(WidgetProxy(wid, this), event);
		return false;
	}

	bool postEvent(Event)(WidgetProxy widget, auto ref Event event)
	{
		if (auto events = widget.get!WidgetEvents)
			return events.postEvent(widget, event);
		return false;
	}

	static bool containsPointer(WidgetId widget, GuiContext context, ivec2 pointerPos)
	{
		auto transform = context.widgets.getOrCreate!WidgetTransform(widget);
		return transform.contains(pointerPos);
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
		updateHovered(state.curPointerPos);
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
		state.pointerPressPos = state.curPointerPos;

		foreach_reverse(root; roots)
		{
			WidgetId[] path = buildPathToLeaf!(containsPointer)(this, root, this, state.curPointerPos);
			WidgetId[] eventConsumerChain = propagateEventSinkBubble(this, path, event, OnHandle.StopTraversing);

			if (eventConsumerChain.length > 0)
			{
				WidgetId consumer = eventConsumerChain[$-1];
				if (widgets.has!WidgetIsFocusable(consumer))
					focusedWidget = consumer;

				if (event.beginDrag) beginDrag(consumer);

				pressedWidget = consumer;
				return;
			}
		}

		focusedWidget = WidgetId(0);
	}

	void pointerReleased(PointerButton button, uint modifiers)
	{
		auto event = PointerReleaseEvent(state.curPointerPos, button, modifiers);
		scope(exit) pressedWidget = WidgetId(0);

		if (draggedWidget)
		{
			endDrag();
			return;
		}

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

					return;
				}
			}
		}

		if (pressedWidget) // no one handled event. Let's pressed widget know that pointer was released.
		{
			postEvent(pressedWidget, event); // pressed widget will know if pointer was unpressed somewhere else.
			updateHovered(state.curPointerPos); // So widget knows if pointer released not over it.
		}
	}

	void pointerMoved(ivec2 newPointerPos)
	{
		if (newPointerPos == state.curPointerPos) return;

		state.prevPointerPos = state.curPointerPos;
		state.curPointerPos = newPointerPos;
		ivec2 delta = state.curPointerPos - state.prevPointerPos;

		auto event = PointerMoveEvent(newPointerPos, delta);

		if (draggedWidget)
		{
			doDrag(delta);
		}
		else if (pressedWidget)
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
			if (updateHovered(newPointerPos, delta)) return;
		}

		hoveredWidget = WidgetId(0);
	}

	private bool updateHovered(ivec2 pointerPos, ivec2 delta = ivec2(0,0))
	{
		foreach_reverse(root; roots)
		{
			WidgetId[] path = buildPathToLeaf!(containsPointer)(this, root, this, pointerPos);
			auto event = PointerMoveEvent(pointerPos, delta);

			foreach_reverse(widget; path)
			{
				postEvent(widget, event);
				if (event.handled)
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
		foreach(root; roots)
			propagateEventSinkBubbleTree!(No.CheckHidden)(this, root, GuiUpdateEvent(deltaTime));

		updateLayout();

		auto drawEvent = DrawEvent(renderQueue);
		foreach(root; roots)
			propagateEventSinkBubbleTree(this, root, drawEvent);
	}

	private void updateLayout()
	{
		foreach(root; roots)
		{
			MeasureEvent measureEvent;
			foreach(widget; visitTreeChildrenFirstVisible(root))
			{
				postEvent(widget, measureEvent);
				auto childTransform = widgets.getOrCreate!WidgetTransform(widget);
				childTransform.size = childTransform.constrainedSize;
			}

			auto trans = widgets.getOrCreate!WidgetTransform(root);
			trans.size = trans.constrainedSize;
			if (trans.hasHexpand) trans.size.x = state.canvasSize.x;
			if (trans.hasVexpand) trans.size.y = state.canvasSize.y;
			trans.absPos = trans.relPos;

			LayoutEvent layoutEvent;
			foreach(widget; visitTreeRootFirstVisible(root))
			{
				postEvent(widget, layoutEvent);
				auto parentTransform = widget.getOrCreate!WidgetTransform;
				foreach(child; widget.children)
				{
					auto childTransform = child.getOrCreate!WidgetTransform;
					childTransform.absPos = parentTransform.absPos + childTransform.relPos;
					childTransform.size.x = max(childTransform.size.x, 0);
					childTransform.size.y = max(childTransform.size.y, 0);
				}
			}
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
		import std.utf : byChar;
		state.setClipboard(cast(string)str.byChar.array);
	}

	void cursorIcon(CursorIcon icon) { state.cursorIcon = icon; }

	void beginDrag(WidgetId wid)
	{
		draggedWidget = wid;
		state.draggedWidgetOffset = state.curPointerPos - get!WidgetTransform(wid).absPos;
		postEvent(wid, DragBeginEvent());
	}

	void doDrag(ivec2 delta)
	{
		assert(draggedWidget);
		postEvent(draggedWidget, DragEvent(delta));
	}

	void endDrag()
	{
		assert(draggedWidget);
		postEvent(draggedWidget, DragEndEvent());
		draggedWidget = WidgetId(0);
		updateHovered(state.curPointerPos);
	}

	WidgetId draggedWidget() { return state.draggedWidget; }
	void draggedWidget(WidgetId wid) { state.draggedWidget = wid; updateHovered(state.curPointerPos); }

	WidgetId focusedWidget() { return state.focusedWidget; }
	void focusedWidget(WidgetId wid)
	{
		if (state.focusedWidget != wid)
		{
			if (state.focusedWidget) postEvent(state.focusedWidget, FocusLoseEvent());
			if (wid) postEvent(wid, FocusGainEvent());
			state.focusedWidget = wid;
		}
	}

	WidgetId hoveredWidget() { return state.hoveredWidget; }
	void hoveredWidget(WidgetId wid) @trusted
	{
		if (state.hoveredWidget != wid)
		{
			if (state.hoveredWidget) postEvent(state.hoveredWidget, PointerLeaveEvent());
			cursorIcon = CursorIcon.arrow;
			if (wid) postEvent(wid, PointerEnterEvent());
			state.hoveredWidget = wid;
		}
	}

	WidgetId inputOwnerWidget() { return state.inputOwnerWidget; }
	void inputOwnerWidget(WidgetId wid) { state.inputOwnerWidget = wid; }

	WidgetId lastClickedWidget() { return state.lastClickedWidget; }
	void lastClickedWidget(WidgetId wid) { state.lastClickedWidget = wid; }

	WidgetId pressedWidget() { return state.pressedWidget; }
	void pressedWidget(WidgetId wid) { state.pressedWidget = wid; updateHovered(state.curPointerPos); }
}
