/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.gui.events;

import voxelman.graphics : RenderQueue;
import voxelman.gui;
import voxelman.math;
public import voxelman.platform.input : KeyCode, PointerButton, KeyModifiers;


private mixin template GuiEvent()
{
	/// If this flag is set - event propagates from root widget to target widget
	/// otherwise it is bubbling from target to root
	bool sinking = true;
	bool bubbling() { return !sinking; }
	bool bubbling(bool newBubbling) { return sinking = !newBubbling; }

	/// Specifies if event was already handled.
	/// Useful for checking if any child has handled this event.
	/// Set automatically by EventPropagator
	bool handled;
}

struct GuiUpdateEvent
{
	double deltaTime;
	mixin GuiEvent!();
}

struct DrawEvent
{
	RenderQueue renderQueue;
	int depth;
	mixin GuiEvent!();
}

private mixin template PointerButtonEvent()
{
	import voxelman.platform.input : PointerButton;
	ivec2 pointerPosition;
	PointerButton button;
	mixin ModifiersMixin!();
	mixin GuiEvent!();
}

struct PointerPressEvent {
	mixin PointerButtonEvent!();
	/// If event consumer sets this to true, then context will begin dragging
	bool beginDrag;
}
struct PointerReleaseEvent { mixin PointerButtonEvent!(); }
struct PointerClickEvent { mixin PointerButtonEvent!(); }
struct PointerDoubleClickEvent { mixin PointerButtonEvent!(); }
struct PointerMoveEvent {
	ivec2 newPointerPos;
	ivec2 delta;
	mixin GuiEvent!();
}
struct ScrollEvent {
	vec2 delta;
	mixin GuiEvent!();
}

struct DragEvent
{
	ivec2 newPointerPos;
	ivec2 delta;
	WidgetId target;
	ivec2 totalDragOffset;
	mixin GuiEvent!();
}

struct DragBeginEvent
{
	DragEvent base;
	alias base this;
}

struct DragEndEvent
{
	DragEvent base;
	alias base this;
}

// Keyboard
struct CharEnterEvent
{
	dchar character;
	mixin GuiEvent!();
}

private mixin template ModifiersMixin()
{
	uint modifiers; // flags from KeyModifiers
	bool shift() { return cast(bool)(modifiers & KeyModifiers.SHIFT); }
	bool control() { return cast(bool)(modifiers & KeyModifiers.CONTROL); }
	bool alt() { return cast(bool)(modifiers & KeyModifiers.ALT); }
}

private mixin template KeyEvent()
{
	KeyCode keyCode;
	mixin ModifiersMixin!();
	mixin GuiEvent!();
}

struct KeyPressEvent { mixin KeyEvent!(); }
struct KeyReleaseEvent { mixin KeyEvent!(); }

// Hovering
struct PointerEnterEvent { mixin GuiEvent!(); }
struct PointerLeaveEvent { mixin GuiEvent!(); }

// Focus
struct FocusGainEvent { mixin GuiEvent!(); }
struct FocusLoseEvent { mixin GuiEvent!(); }

// Layout
struct MeasureEvent {}
struct  LayoutEvent {}

// Misc
struct GroupSelectionEvent
{
	WidgetId selected;
	mixin GuiEvent!();
}
