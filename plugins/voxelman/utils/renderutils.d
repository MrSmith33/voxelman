/**
Copyright: Copyright (c) 2014-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.utils.renderutils;

import std.experimental.logger;

import derelict.opengl3.gl3;
import voxelman.math;
import voxelman.model.vertex;

import voxelman.block.utils : Side, faces;

alias ColoredVertex = VertexPosColor!(float, ubyte);

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


Color3ub[] colorsArray =
[
Colors.black, Colors.white, Colors.red,
Colors.green, Colors.blue, Colors.cyan,
Colors.magenta, Colors.yellow
];

struct Batch
{
	ColoredVertex[] triBuffer;
	ColoredVertex[] lineBuffer;
	ColoredVertex[] pointBuffer;

	void putCube(vec3 pos, vec3 size, Color3ub color, bool fill)
	{
		if (fill)
			putFilledBlock(triBuffer, pos, size, color);
		else
			putLineBlock(lineBuffer, pos, size, color);
	}

	void putCubeFace(vec3 cubePos, vec3 size, Side side, Color3ub color, bool fill)
	{
		if (fill)
			putFilledSide(triBuffer, cubePos, size, side, color);
		else
			putLineSide(lineBuffer, cubePos, size, side, color);
	}

	void putLine(vec3 start, vec3 end, Color3ub color)
	{
		if (lineBuffer.capacity - lineBuffer.length < 2)
			lineBuffer.reserve(lineBuffer.capacity + 1024);

		lineBuffer ~= ColoredVertex(start, color);
		lineBuffer ~= ColoredVertex(end, color);
	}

	void putPoint(vec3 pos, Color3ub color)
	{
		if (pointBuffer.capacity - pointBuffer.length < 1)
			pointBuffer.reserve(pointBuffer.capacity + 1024);

		pointBuffer ~= ColoredVertex(pos, color);
	}

	void put3dGrid(vec3 pos, ivec3 count, vec3 offset, Color3ub color)
	{
		// x
		foreach(i; 0..count.y)
		foreach(j; 0..count.z)
		{
			float y = pos.y + i * offset.y;
			float z = pos.z + j * offset.z;
			vec3 start = vec3(pos.x, y, z);
			vec3 end = vec3(pos.x + (count.x-1) * offset.x, y, z);
			putLine(start, end, color);
		}

		// y
		foreach(i; 0..count.x)
		foreach(j; 0..count.z)
		{
			float x = pos.x + i * offset.x;
			float z = pos.z + j * offset.z;
			vec3 start = vec3(x, pos.y, z);
			vec3 end = vec3(x, pos.y + (count.y-1) * offset.y, z);
			putLine(start, end, color);
		}

		// z
		foreach(i; 0..count.x)
		foreach(j; 0..count.y)
		{
			float x = pos.x + i * offset.x;
			float y = pos.y + j * offset.y;
			vec3 start = vec3(x, y, pos.z);
			vec3 end = vec3(x, y, pos.z + (count.z-1) * offset.z);
			putLine(start, end, color);
		}
	}

	void reset()
	{
		resetBuffer(triBuffer);
		resetBuffer(lineBuffer);
		resetBuffer(pointBuffer);
	}
}

void resetBuffer(ref ColoredVertex[] buffer)
{
	buffer.length = 0;
	assumeSafeAppend(buffer);
}

void putFilledBlock(ref ColoredVertex[] output, vec3 pos, vec3 size, Color3ub color)
{
	output.reserve(6 * 6); // 6 faces, 6 points per edge

	for (size_t i = 0; i!=18*6; i+=3)
	{
		auto v = ColoredVertex(
			faces[i  ]*size.x + pos.x,
			faces[i+1]*size.y + pos.y,
			faces[i+2]*size.z + pos.z,
			color);
		output ~= v;
	}
}

void putLineBlock(ref ColoredVertex[] output, vec3 pos, vec3 size, Color3ub color)
{
	output.reserve(12 * 2); // 12 edges, 2 points per edge

	for (size_t i = 0; i!=12*2*3; i+=3)
	{
		auto v = ColoredVertex(
			cubeLines[i  ]*size.x + pos.x,
			cubeLines[i+1]*size.y + pos.y,
			cubeLines[i+2]*size.z + pos.z,
			color);
		output ~= v;
	}
}

void putFilledSide(ref ColoredVertex[] output, vec3 pos, vec3 size, Side side, Color3ub color)
{
	output.reserve(6);

	for (size_t i = side * 18; i!=side*18+18; i+=3)
	{
		auto v = ColoredVertex(
			faces[i  ]*size.x + pos.x,
			faces[i+1]*size.y + pos.y,
			faces[i+2]*size.z + pos.z,
			color);
		output ~= v;
	}
}

void putLineSide(ref ColoredVertex[] output, vec3 pos, vec3 size, Side side, Color3ub color)
{
	output.reserve(6);

	for (size_t i = side * 24; i!=side*24+24; i+=3)
	{
		auto v = ColoredVertex(
			cubeLineSides[i  ]*size.x + pos.x,
			cubeLineSides[i+1]*size.y + pos.y,
			cubeLineSides[i+2]*size.z + pos.z,
			color);
		output ~= v;
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
	0, 0, 0, // north
	1, 0, 0,
	0, 1, 0,
	1, 1, 0,
	0, 0, 0,
	0, 1, 0,
	1, 0, 0,
	1, 1, 0,

	0, 0, 1, // south
	1, 0, 1,
	0, 1, 1,
	1, 1, 1,
	0, 0, 1,
	0, 1, 1,
	1, 0, 1,
	1, 1, 1,

	1, 0, 0, // east
	1, 0, 1,
	1, 1, 0,
	1, 1, 1,
	1, 0, 0,
	1, 1, 0,
	1, 0, 1,
	1, 1, 1,

	0, 0, 0, // west
	0, 0, 1,
	0, 1, 0,
	0, 1, 1,
	0, 0, 0,
	0, 1, 0,
	0, 0, 1,
	0, 1, 1,

	1, 1, 1, // top
	0, 1, 1,
	1, 1, 0,
	0, 1, 0,
	1, 1, 1,
	1, 1, 0,
	0, 1, 1,
	0, 1, 0,

	1, 0, 1, // bottom
	0, 0, 1,
	1, 0, 0,
	0, 0, 0,
	1, 0, 1,
	1, 0, 0,
	0, 0, 1,
	0, 0, 0,
];
