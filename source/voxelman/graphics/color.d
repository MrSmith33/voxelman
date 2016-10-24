/**
Copyright: Copyright (c) 2016 Andrey Penechko.
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
}


Color4ub[] colorsArray = [
	Colors.black, Colors.white, Colors.red,
	Colors.green, Colors.blue, Colors.cyan,
	Colors.magenta, Colors.yellow
];
