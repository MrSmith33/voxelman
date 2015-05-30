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

class Draw1Event : GameEvent {
	this(IRenderer renderer)
	{
		this.renderer = renderer;
	}
	IRenderer renderer;
}
class Draw2Event : GameEvent {
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
