/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.utils.linebuffer;

struct LineBuffer
{
	import derelict.imgui.imgui;
	import std.array : empty;
	import std.format : formattedWrite;
	import voxelman.container.buffer;

	Buffer!char lines;
	Buffer!size_t lineSizes;
	bool scrollToBottom;

	void clear()
	{
		lines.clear();
		lineSizes.clear();
	}

	void put(in char[] str)
	{
		import std.regex : ctRegex, splitter;
		import std.algorithm : map;
		import std.range;

		if (str.empty) return;
		auto splittedLines = splitter(str, ctRegex!"(\r\n|\r|\n|\v|\f)");

		foreach(first; splittedLines.takeOne())
		{
			lines.put(first);
			if (!lineSizes.data.empty)
			{
				lineSizes.data[$-1] += first.length;
			}
			else
			{
				lineSizes.put(first.length);
			}
		}

		// process other lines
		foreach(line; splittedLines.drop(1))
		{
			++lineSizes.data[$-1];
			lines.put("\n");
			lines.put(line);
			lineSizes.put(line.length);
		}

		scrollToBottom = true;
	}

	void putf(Args...)(const(char)[] fmt, Args args)
	{
		formattedWrite(&this, fmt, args);
	}

	void putfln(Args...)(const(char)[] fmt, Args args)
	{
		formattedWrite(&this, fmt, args);
		put("\n");
	}

	void putln(const(char)[] str)
	{
		put(str);
		put("\n");
	}

	void draw()
	{
		char* lineStart = lines.data.ptr;
		foreach(lineSize; lineSizes.data)
		if (lineSize > 0)
		{
			igPushTextWrapPos(igGetWindowContentRegionWidth());
			igTextUnformatted(lineStart, lineStart+lineSize);
			igPopTextWrapPos();
			lineStart += lineSize;
		}

		if (scrollToBottom)
			igSetScrollHere(1.0f);
		scrollToBottom = false;
	}

	void drawSelectable()
	{
		igPushStyleVarVec(ImGuiStyleVar_FramePadding, ImVec2(6,6));

		ImVec2 size;
		igGetContentRegionAvail(&size);
		size.x -= 12;
		size.y -= 12;

		igPushStyleColor(ImGuiCol_FrameBg, ImVec4(0, 0, 0, 0));
		if (lines.data.length)
			igInputTextMultiline("##multiline", lines.data.ptr, lines.data.length, size, ImGuiInputTextFlags_ReadOnly);
		else
		{
			char[] str = cast(char[])"";
			igInputTextMultiline("##multiline", str.ptr, str.length, size, ImGuiInputTextFlags_ReadOnly);
		}
		igPopStyleColor();

		igPopStyleVar();

		if (scrollToBottom)
			igSetScrollHere(1.0f);
		scrollToBottom = false;
	}
}
