/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.core.events;

import anchovy.irenderer;
import dlib.math.vector;
import tharsis.prof : Profiler;

struct GameStopEvent {
	Profiler profiler;
	bool continuePropagation = true;
}

struct UpdateEvent {
	double deltaTime;
	Profiler profiler;
	bool continuePropagation = true;
}
struct PreUpdateEvent {
	double deltaTime;
	Profiler profiler;
	bool continuePropagation = true;
}
struct PostUpdateEvent {
	double deltaTime;
	Profiler profiler;
	bool continuePropagation = true;
}

// Initiate drawing in graphics plugin
struct RenderEvent {
	Profiler profiler;
	bool continuePropagation = true;
}

// draw in 3d. With depth test
struct Render1Event {
	IRenderer renderer;
	Profiler profiler;
	bool continuePropagation = true;
}

// draw 2d. without depth test. with alpha
struct Render2Event {
	IRenderer renderer;
	Profiler profiler;
	bool continuePropagation = true;
}
// draw 2d gui. without depth test. with alpha
struct Render3Event {
	IRenderer renderer;
	Profiler profiler;
	bool continuePropagation = true;
}

struct WindowResizedEvent
{
	uvec2 newSize;
	Profiler profiler;
	bool continuePropagation = true;
}
