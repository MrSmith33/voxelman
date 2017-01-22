/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.graphics.batch;

import voxelman.container.buffer;
import voxelman.model.vertex;
import voxelman.geometry.cube : CubeSide;
import voxelman.math;
import voxelman.graphics;

alias ColoredVertex = VertexPosColor!(float, 3, ubyte, 4);

struct Batch
{
	Buffer!ColoredVertex triBuffer;
	Buffer!ColoredVertex lineBuffer;
	Buffer!ColoredVertex pointBuffer;

	void putCube(T1, T2)(Vector!(T1, 3) pos, Vector!(T2, 3) size, Color4ub color, bool fill)
	{
		if (fill)
			putFilledBlock(triBuffer, pos, size, color);
		else
			putLineBlock(lineBuffer, pos, size, color);
	}

	void putCubeFace(T1, T2)(Vector!(T1, 3) cubePos, Vector!(T2, 3) size, CubeSide side, Color4ub color, bool fill)
	{
		if (fill)
			putFilledSide(triBuffer, cubePos, size, side, color);
		else
			putLineSide(lineBuffer, cubePos, size, side, color);
	}

	void putLine(T1, T2)(Vector!(T1, 3) start, Vector!(T2, 3) end, Color4ub color)
	{
		lineBuffer.put(
			ColoredVertex(start, color),
			ColoredVertex(end, color));
	}

	void putPoint(T)(Vector!(T, 3) pos, Color4ub color)
	{
		pointBuffer.put(ColoredVertex(pos, color));
	}

	void put3dGrid(T1, T2)(Vector!(T1, 3) pos, ivec3 count, Vector!(T2, 3) offset, Color4ub color)
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
		triBuffer.clear();
		lineBuffer.clear();
		pointBuffer.clear();
	}
}
