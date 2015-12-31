/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.utils.textformatter;

import std.array;
import std.format;

char[4*1024] buf;
Appender!(char[]) app;

static this()
{
	app = appender(buf[]);
}

static struct TextPtrs {
	char* start;
	char* end;
}

TextPtrs makeFormattedText(Args ...)(string fmt, Args args) {
	app.clear();
	formattedWrite(app, fmt, args);
	app.put("\0");
	return TextPtrs(app.data.ptr, app.data.ptr + app.data.length - 1);
}

void igTextf(Args ...)(string fmt, Args args)
{
	import derelict.imgui.imgui : igTextUnformatted;
	TextPtrs pair = makeFormattedText(fmt, args);
	igTextUnformatted(pair.start, pair.end);
}
