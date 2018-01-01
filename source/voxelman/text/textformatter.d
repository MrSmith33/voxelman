/**
Copyright: Copyright (c) 2015-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.text.textformatter;

import std.array;
import std.format;
import std.range;

char[4*1024] buf;
Appender!(char[]) app;

static this()
{
	app = appender(buf[]);
}

const(char)[] makeFormattedText(Args ...)(string fmt, Args args) {
	app.clear();
	formattedWrite(app, fmt, args);
	return app.data;
}
