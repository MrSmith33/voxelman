/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.client.console;


struct Console
{
	import voxelman.utils.linebuffer : LineBuffer;
	LineBuffer lineBuffer;
	char[] inputBuf;
	void delegate(string command) commandHandler;

	void init()
	{
		inputBuf = new char[](1024);
	}

	void draw()
	{
		import derelict.imgui.imgui;
		import std.string;
		igBegin("Console");
		igBeginChildEx(0, ImVec2(0,-igGetItemsLineHeightWithSpacing()),
			true, ImGuiWindowFlags_HorizontalScrollbar);
		lineBuffer.draw();
		igEndChild();
		igSetNextWindowSize(ImVec2(0,0));
		if (igInputText("##ConsoleInput", inputBuf.ptr, inputBuf.length,
			ImGuiInputTextFlags_EnterReturnsTrue,
			null, null))
		{
			auto command = cast(string)(inputBuf.ptr.fromStringz).strip;
			if (command.length > 0)
			{
				commandHandler(command);
				inputBuf[] = '\0';
			}
			if (igIsItemHovered() || (igIsRootWindowOrAnyChildFocused() && !igIsAnyItemActive() && !igIsMouseClicked(0)))
				igSetKeyboardFocusHere(-1); // Auto focus previous widget
		}

		igEnd();
	}
}
