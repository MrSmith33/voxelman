/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.utils.linebuffer;

struct LineBuffer
{
	import derelict.imgui.imgui;
	import std.array : Appender, empty;
	import std.format : formattedWrite;

	Appender!(char[]) lines;
	Appender!(size_t[]) lineSizes;
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
		if (str.empty) return;
		auto splittedLines = splitter(str, ctRegex!"(\r\n|\r|\n|\v|\f)");
		auto lengths = splittedLines.map!(a => a.length);
		if (!lineSizes.data.empty)
		{
			lineSizes.data[$-1] += lengths.front;
			lengths.popFront();
		}
		lineSizes.put(lengths);
		foreach(line; splittedLines)
			lines.put(line);
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
}
