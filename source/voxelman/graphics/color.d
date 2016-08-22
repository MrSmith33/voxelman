/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.graphics.color;

import voxelman.math : Vector;

alias Color3ub = Vector!(ubyte, 3);

enum Colors : Color3ub
{
	black = Color3ub(0, 0, 0),
	white = Color3ub(255, 255, 255),
	red = Color3ub(255, 0, 0),
	green = Color3ub(0, 255, 0),
	blue = Color3ub(0, 0, 255),
	cyan = Color3ub(0, 255, 255),
	magenta = Color3ub(255, 0, 255),
	yellow = Color3ub(255, 255, 0),
	gray = Color3ub(128, 128, 128),
}


Color3ub[] colorsArray = [
	Colors.black, Colors.white, Colors.red,
	Colors.green, Colors.blue, Colors.cyan,
	Colors.magenta, Colors.yellow
];
