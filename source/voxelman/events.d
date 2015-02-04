/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.events;

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