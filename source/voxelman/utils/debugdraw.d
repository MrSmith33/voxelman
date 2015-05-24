/**
Copyright: Copyright (c) 2014-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.utils.debugdraw;

import std.experimental.logger;

import derelict.opengl3.gl3;
import dlib.math.vector;

import voxelman.basicblocks : faces;
import voxelman.block : Side;


align(4) struct ColoredVertex
{
	vec3 pos;
	Vector!(ubyte, 3) color;
}

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
}

struct Batch
{
	ColoredVertex[] triBuffer;
	ColoredVertex[] lineBuffer;
	ColoredVertex[] pointBuffer;

	void putCube(vec3 pos, vec3 size, Vector!(ubyte, 3) color, bool fill)
	{
		if (fill)
			putFilledBlock(triBuffer, pos, size, color);
		else
			putLineBlock(lineBuffer, pos, size, color);
	}

	void putCubeFace(vec3 cubePos, vec3 size, Side side, Vector!(ubyte, 3) color, bool fill)
	{
		if (fill)
			putFilledSide(triBuffer, cubePos, size, side, color);
		else
			putLineSide(lineBuffer, cubePos, size, side, color);
	}

	void putLine(vec3 start, vec3 end, Vector!(ubyte, 3) color)
	{
		if (lineBuffer.capacity - lineBuffer.length < 2)
			lineBuffer.reserve(lineBuffer.capacity + 1024);

		lineBuffer ~= ColoredVertex(start, color);
		lineBuffer ~= ColoredVertex(end, color);
	}

	void putPoint(vec3 pos, Vector!(ubyte, 3) color)
	{
		if (pointBuffer.capacity - pointBuffer.length < 1)
			pointBuffer.reserve(pointBuffer.capacity + 1024);

		pointBuffer ~= ColoredVertex(pos, color);
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

struct DebugDraw
{
	void init()
	{
		glGenVertexArrays(1, &vao);
		glGenBuffers( 1, &vbo);
	}

	void draw(Batch batch)
	{
		drawBuffer(batch.triBuffer, GL_TRIANGLES);
		drawBuffer(batch.lineBuffer, GL_LINES);
		drawBuffer(batch.pointBuffer, GL_POINTS);
	}

private:

	void drawBuffer(ref ColoredVertex[] buffer, uint mode)
	{
		if (buffer.length == 0) return;

		glBindVertexArray(vao);
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glBufferData(GL_ARRAY_BUFFER, buffer.length*ColoredVertex.sizeof, buffer.ptr, GL_DYNAMIC_DRAW);
		glEnableVertexAttribArray(0);
		glEnableVertexAttribArray(1);
		// positions
		glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, ColoredVertex.sizeof, null);
		// color
		glVertexAttribPointer(1, 3, GL_UNSIGNED_BYTE, GL_TRUE, ColoredVertex.sizeof, cast(void*)(12));
		glBindBuffer(GL_ARRAY_BUFFER, 0);

		glDrawArrays(mode, 0, cast(uint)(buffer.length));

		glBindVertexArray(0);
	}

	uint vao;
	uint vbo;
}

void putFilledBlock(ref ColoredVertex[] output, vec3 pos, vec3 size, Vector!(ubyte, 3) color)
{
	output.reserve(6 * 6); // 6 faces, 6 points per edge

	for (size_t i = 0; i!=18*6; i+=3)
	{
		ColoredVertex v;
		v.pos.x = faces[i]*size.x + pos.x;
		v.pos.y = faces[i+1]*size.y + pos.y;
		v.pos.z = faces[i+2]*size.z + pos.z;
		v.color = color;
		output ~= v;
	}
}

void putLineBlock(ref ColoredVertex[] output, vec3 pos, vec3 size, Vector!(ubyte, 3) color)
{
	output.reserve(12 * 2); // 12 edges, 2 points per edge

	for (size_t i = 0; i!=12*2*3; i+=3)
	{
		ColoredVertex v;
		v.pos.x = cubeLines[i]*size.x + pos.x;
		v.pos.y = cubeLines[i+1]*size.y + pos.y;
		v.pos.z = cubeLines[i+2]*size.z + pos.z;
		v.color = color;
		output ~= v;
	}
}

void putFilledSide(ref ColoredVertex[] output, vec3 pos, vec3 size, Side side, Vector!(ubyte, 3) color)
{
	output.reserve(6);

	for (size_t i = side * 18; i!=side*18+18; i+=3)
	{
		ColoredVertex v;
		v.pos.x = faces[i]*size.x + pos.x;
		v.pos.y = faces[i+1]*size.y + pos.y;
		v.pos.z = faces[i+2]*size.z + pos.z;
		v.color = color;
		output ~= v;
	}
}

void putLineSide(ref ColoredVertex[] output, vec3 pos, vec3 size, Side side, Vector!(ubyte, 3) color)
{
	output.reserve(6);

	for (size_t i = side * 24; i!=side*24+24; i+=3)
	{
		ColoredVertex v;
		v.pos.x = cubeLineSides[i]*size.x + pos.x;
		v.pos.y = cubeLineSides[i+1]*size.y + pos.y;
		v.pos.z = cubeLineSides[i+2]*size.z + pos.z;
		v.color = color;
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
