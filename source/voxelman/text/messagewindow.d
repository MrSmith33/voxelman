/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.text.messagewindow;

struct MessageWindow
{
	import voxelman.text.linebuffer : LineBuffer;
	LineBuffer lineBuffer;
	alias lineBuffer this;
	char[] inputBuf;
	void delegate(string command) messageHandler;

	void init()
	{
		import std.array : uninitializedArray;
		inputBuf = uninitializedArray!(char[])(1024);
		inputBuf[0] = '\0';
	}
/*
	void draw(bool drawBorder = true)
	{
		import std.string;

		igPushStyleVarVec(ImGuiStyleVar_WindowPadding, ImVec2(0,0));
		igBeginChildEx(0, ImVec2(0,-igGetItemsLineHeightWithSpacing()),
			drawBorder, ImGuiWindowFlags_HorizontalScrollbar);
		lineBuffer.drawSelectable();
		igEndChild();
		igPopStyleVar();


		bool press = false;

		igPushItemWidth(igGetContentRegionAvailWidth()-60);
		if (igInputText("##input", inputBuf.ptr, inputBuf.length, ImGuiInputTextFlags_EnterReturnsTrue, null, null))
		{
			press = true;
		}

		igPopItemWidth();
		igSameLine();
		press = press || igButton("Enter");

		if (press)
		{
			auto command = cast(string)(inputBuf.ptr.fromStringz).strip;
			if (command.length > 0)
			{
				messageHandler(command);
				inputBuf[] = '\0';
			}
			if (igIsItemHovered() || (igIsRootWindowOrAnyChildFocused() && !igIsAnyItemActive() && !igIsMouseClicked(0)))
				igSetKeyboardFocusHere(-2); // Auto focus input
		}
	}*/
}
