/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.core.events;

import anchovy.irenderer;
import voxelman.math;

struct GameStartEvent {}
struct GameStopEvent {}

struct PreUpdateEvent {
	double deltaTime;
	ulong frame;
}
struct UpdateEvent {
	double deltaTime;
	ulong frame;
}
struct PostUpdateEvent {
	double deltaTime;
	ulong frame;
}
struct DoGuiEvent {
	ulong frame;
}

struct WorldSaveEvent {}

// Initiate drawing in graphics plugin
struct RenderEvent {}

// draw in 3d. With depth test
struct Render1Event {
	IRenderer renderer;
}

// draw in 3d. With depth test
struct RenderSolid3dEvent {
	IRenderer renderer;
}

// draw in 3d. With depth test
struct RenderTransparent3dEvent {
	IRenderer renderer;
}

// draw 2d. without depth test. with alpha
struct Render2Event {
	IRenderer renderer;
}
// draw 2d gui. without depth test. with alpha
struct Render3Event {
	IRenderer renderer;
}

struct WindowResizedEvent
{
	uvec2 newSize;
}

// emitted only by server plugin
struct WorldSaveInternalEvent {}
