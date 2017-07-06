/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.graphics.color;

import voxelman.math : Vector;

alias Color4ub = Vector!(ubyte, 4);

enum Colors : Color4ub
{
	black = Color4ub(0, 0, 0, 255),
	white = Color4ub(255, 255, 255, 255),
	red = Color4ub(255, 0, 0, 255),
	green = Color4ub(0, 255, 0, 255),
	blue = Color4ub(0, 0, 255, 255),
	cyan = Color4ub(0, 255, 255, 255),
	magenta = Color4ub(255, 0, 255, 255),
	yellow = Color4ub(255, 255, 0, 255),
	gray = Color4ub(128, 128, 128, 255),
	orange = Color4ub(255, 128, 0, 255),
	orangeRed = Color4ub(255, 69, 0, 255),
	pink = Color4ub(255, 192, 203, 255),
	brown = Color4ub(128, 64, 0, 255),
	purple = Color4ub(128, 0, 128, 255),
	indigo = Color4ub(75, 0, 128, 255),
	violet = Color4ub(143, 0, 255, 255),
}


Color4ub[] colorsArray = [
	Colors.black, Colors.white, Colors.red,
	Colors.green, Colors.blue, Colors.cyan,
	Colors.magenta, Colors.yellow, Colors.gray,
	Colors.orange, Colors.orangeRed, Colors.pink,
	Colors.brown, Colors.purple, Colors.indigo,
	Colors.violet,
];

Color4ub rgb(ubyte r, ubyte g, ubyte b)
{
	return Color4ub(r, g, b, 255);
}
