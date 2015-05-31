/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.events;

import anchovy.graphics.interfaces.irenderer;
import dlib.math.vector;
import voxelman.plugins.eventdispatcherplugin : GameEvent;


class GameStopEvent : GameEvent {}

class UpdateEvent : GameEvent {
	this(double dt)
	{
		deltaTime = dt;
	}
	double deltaTime;
}
class PreUpdateEvent : UpdateEvent {
	this(double dt) {
		super(dt);
	}
}
class PostUpdateEvent : UpdateEvent {
	this(double dt) {
		super(dt);
	}
}

// Initiate drawing in graphics plugin
class RenderEvent : GameEvent {
}

// draw in 3d. With depth test
class Render1Event : GameEvent {
	this(IRenderer renderer)
	{
		this.renderer = renderer;
	}
	IRenderer renderer;
}

// draw 2d. without depth test. with alpha
class Render2Event : GameEvent {
	this(IRenderer renderer)
	{
		this.renderer = renderer;
	}
	IRenderer renderer;
}
// draw 2d gui. without depth test. with alpha
class Render3Event : GameEvent {
	this(IRenderer renderer)
	{
		this.renderer = renderer;
	}
	IRenderer renderer;
}

class WindowResizedEvent : GameEvent
{
	this(uvec2 size)
	{
		newSize = size;
	}
	uvec2 newSize;
}
