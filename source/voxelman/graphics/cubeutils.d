/**
Copyright: Copyright (c) 2014-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.graphics.cubeutils;

import voxelman.log;

import voxelman.container.buffer;

import voxelman.geometry.cube : CubeSide, cubeFaces;
import voxelman.math;
import voxelman.graphics;


void putFilledBlock(V)(ref Buffer!V output, vec3 pos, vec3 size, Color4ub color)
{
	output.reserve(6 * 6); // 6 faces, 6 points per edge

	for (size_t i = 0; i!=18*6; i+=3)
	{
		auto v = V(
			cubeFaces[i  ]*size.x + pos.x,
			cubeFaces[i+1]*size.y + pos.y,
			cubeFaces[i+2]*size.z + pos.z,
			color);
		output.put(v);
	}
}

void putLineBlock(V)(ref Buffer!V output, vec3 pos, vec3 size, Color4ub color)
{
	output.reserve(12 * 2); // 12 edges, 2 points per edge

	for (size_t i = 0; i!=12*2*3; i+=3)
	{
		auto v = V(
			cubeLines[i  ]*size.x + pos.x,
			cubeLines[i+1]*size.y + pos.y,
			cubeLines[i+2]*size.z + pos.z,
			color);
		output.put(v);
	}
}

void putFilledSide(V)(ref Buffer!V output, vec3 pos, vec3 size, CubeSide side, Color4ub color)
{
	output.reserve(6);

	for (size_t i = side * 18; i!=side*18+18; i+=3)
	{
		auto v = V(
			cubeFaces[i  ]*size.x + pos.x,
			cubeFaces[i+1]*size.y + pos.y,
			cubeFaces[i+2]*size.z + pos.z,
			color);
		output.put(v);
	}
}

void putLineSide(V)(ref Buffer!V output, vec3 pos, vec3 size, CubeSide side, Color4ub color)
{
	output.reserve(8); // 4 edges, 2 points per edge

	for (size_t i = side * 24; i!=side*24+24; i+=3)
	{
		auto v = V(
			cubeLineSides[i  ]*size.x + pos.x,
			cubeLineSides[i+1]*size.y + pos.y,
			cubeLineSides[i+2]*size.z + pos.z,
			color);
		output.put(v);
	}
}

immutable ubyte[] cubeLines =
[
	0, 0, 0,  1, 0, 0,
	1, 0, 0,  1, 0, 1,
	1, 0, 1,  0, 0, 1,
	0, 0, 1,  0, 0, 0,

	0, 1, 0,  1, 1, 0,
	1, 1, 0,  1, 1, 1,
	1, 1, 1,  0, 1, 1,
	0, 1, 1,  0, 1, 0,

	0, 0, 0,  0, 1, 0,
	1, 0, 0,  1, 1, 0,
	1, 0, 1,  1, 1, 1,
	0, 0, 1,  0, 1, 1,
];

immutable ubyte[] cubeLineSides =
[
	0, 0, 0, // zneg
	1, 0, 0,
	0, 1, 0,
	1, 1, 0,
	0, 0, 0,
	0, 1, 0,
	1, 0, 0,
	1, 1, 0,

	0, 0, 1, // zpos
	1, 0, 1,
	0, 1, 1,
	1, 1, 1,
	0, 0, 1,
	0, 1, 1,
	1, 0, 1,
	1, 1, 1,

	1, 0, 0, // xpos
	1, 0, 1,
	1, 1, 0,
	1, 1, 1,
	1, 0, 0,
	1, 1, 0,
	1, 0, 1,
	1, 1, 1,

	0, 0, 0, // xneg
	0, 0, 1,
	0, 1, 0,
	0, 1, 1,
	0, 0, 0,
	0, 1, 0,
	0, 0, 1,
	0, 1, 1,

	1, 1, 1, // ypos
	0, 1, 1,
	1, 1, 0,
	0, 1, 0,
	1, 1, 1,
	1, 1, 0,
	0, 1, 1,
	0, 1, 0,

	1, 0, 1, // yneg
	0, 0, 1,
	1, 0, 0,
	0, 0, 0,
	1, 0, 1,
	1, 0, 0,
	0, 0, 1,
	0, 0, 0,
];
