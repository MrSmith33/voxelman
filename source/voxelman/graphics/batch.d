/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.graphics.batch;

import voxelman.container.buffer;
import voxelman.model.vertex;
import voxelman.geometry.cube : CubeSide;
import voxelman.math;
import voxelman.graphics;

alias ColoredVertex = VertexPosColor!(float, ubyte);

struct Batch
{
	Buffer!ColoredVertex triBuffer;
	Buffer!ColoredVertex lineBuffer;
	Buffer!ColoredVertex pointBuffer;

	void putCube(vec3 pos, vec3 size, Color3ub color, bool fill)
	{
		if (fill)
			putFilledBlock(triBuffer, pos, size, color);
		else
			putLineBlock(lineBuffer, pos, size, color);
	}

	void putCubeFace(vec3 cubePos, vec3 size, CubeSide side, Color3ub color, bool fill)
	{
		if (fill)
			putFilledSide(triBuffer, cubePos, size, side, color);
		else
			putLineSide(lineBuffer, cubePos, size, side, color);
	}

	void putLine(vec3 start, vec3 end, Color3ub color)
	{
		lineBuffer.put(
			ColoredVertex(start, color),
			ColoredVertex(end, color));
	}

	void putPoint(vec3 pos, Color3ub color)
	{
		pointBuffer.put(ColoredVertex(pos, color));
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
		triBuffer.clear();
		lineBuffer.clear();
		pointBuffer.clear();
	}
}
