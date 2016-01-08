/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.client.console;

import std.experimental.logger;

struct Console
{
	import voxelman.utils.messagewindow : MessageWindow;
	MessageWindow messageWindow;
	alias messageWindow this;

	void init()
	{
		messageWindow.init();
	}

	void draw()
	{
		import derelict.imgui.imgui;
		igSetNextWindowPosCenter(ImGuiSetCond_FirstUseEver);
		igSetNextWindowSize(ImVec2(400, 300), ImGuiSetCond_FirstUseEver);
		if (!igBegin("Console")) return;
		messageWindow.draw();
		igEnd();
	}
}
