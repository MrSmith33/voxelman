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

struct DebugDraw
{
	void init()
	{
		lineBuffer.reserve(1024*1024);
		triBuffer.reserve(1024*1024);

		glGenBuffers( 1, &lineVbo);
		glGenVertexArrays(1, &lineVao);
		glGenBuffers( 1, &triVbo);
		glGenVertexArrays(1, &triVao);
	}

	void drawCube(vec3 pos, vec3 size, Vector!(ubyte, 3) color, bool fill)
	{
		if (fill)
			putFilledBlock(triBuffer, pos, size, color);
		else
			putLineBlock(lineBuffer, pos, size, color);
	}

	void drawLine(vec3 start, vec3 end, Vector!(ubyte, 3) color)
	{
		if (lineBuffer.capacity - lineBuffer.length < 2)
			lineBuffer.reserve(lineBuffer.capacity + 1024);

		lineBuffer ~= ColoredVertex(start, color);
		lineBuffer ~= ColoredVertex(end, color);
	}

	void flush()
	{
		drawBuffer(triBuffer, true, triVao, triVbo);
		drawBuffer(lineBuffer, false, lineVao, lineVbo);
	}

private:

	void drawBuffer(ref ColoredVertex[] buffer, bool fill, uint vao, uint vbo)
	{
		if (buffer.length == 0) return;

		glBindVertexArray(vao);
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glBufferData(GL_ARRAY_BUFFER, buffer.length*ColoredVertex.sizeof, buffer.ptr, GL_STATIC_DRAW);
		glEnableVertexAttribArray(0);
		glEnableVertexAttribArray(1);
		// coords
		glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, ColoredVertex.sizeof, null);
		// color
		glVertexAttribPointer(1, 3, GL_UNSIGNED_BYTE, GL_TRUE, ColoredVertex.sizeof, cast(void*)(12));
		glBindBuffer(GL_ARRAY_BUFFER, 0);

		if (fill)
			glDrawArrays(GL_TRIANGLES, 0, cast(uint)(buffer.length));
		else
			glDrawArrays(GL_LINES, 0, cast(uint)(buffer.length));

		glBindVertexArray(0);

		buffer.length = 0;
		assumeSafeAppend(buffer);
	}

	ColoredVertex[] lineBuffer;
	ColoredVertex[] triBuffer;

	uint lineVao;
	uint lineVbo;
	uint triVao;
	uint triVbo;
}

void putFilledBlock(ref ColoredVertex[] output, vec3 pos, vec3 size, Vector!(ubyte, 3) color)
{
	output.reserve(ColoredVertex.sizeof * 6 * 6); // 6 faces, 6 points per edge

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
	output.reserve(ColoredVertex.sizeof * 12 * 2); // 12 edges, 2 points per edge

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
