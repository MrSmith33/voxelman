/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.graphics.batch2d;

import voxelman.container.buffer;
import voxelman.model.vertex;
import voxelman.math;
import voxelman.graphics;

alias ColoredVertex2d = VertexPosColor!(float, 2, ubyte, 4);

struct Batch2d
{
	Buffer!ColoredVertex2d triBuffer;
	Buffer!ColoredVertex2d lineBuffer;
	Buffer!ColoredVertex2d pointBuffer;

	void putRect(vec2 pos, vec2 size, Color4ub color, bool fill)
	{
		enum vec2 offset = vec2(0, 0);// 0.375
		if (fill) {
			triBuffer.put(
				ColoredVertex2d(offset + pos, color),
				ColoredVertex2d(offset + vec2(pos.x + size.x, pos.y), color),
				ColoredVertex2d(offset + vec2(pos.x, pos.y + size.y), color),
				ColoredVertex2d(offset + vec2(pos.x, pos.y + size.y), color),
				ColoredVertex2d(offset + vec2(pos.x + size.x, pos.y), color),
				ColoredVertex2d(offset + vec2(pos.x + size.x, pos.y + size.y), color));
		} else {
			lineBuffer.put(
				ColoredVertex2d(offset + pos, color),
				ColoredVertex2d(offset + vec2(pos.x + size.x, pos.y), color),
				ColoredVertex2d(offset + vec2(pos.x + size.x, pos.y), color),
				ColoredVertex2d(offset + vec2(pos.x + size.x, pos.y + size.y), color),
				ColoredVertex2d(offset + vec2(pos.x + size.x, pos.y + size.y), color),
				ColoredVertex2d(offset + vec2(pos.x, pos.y + size.y), color),
				ColoredVertex2d(offset + vec2(pos.x, pos.y + size.y), color),
				ColoredVertex2d(offset + vec2(pos.x, pos.y - 1), color));
		}
	}

	void putLine(vec2 start, vec2 end, Color4ub color)
	{
		lineBuffer.put(
			ColoredVertex2d(start, color),
			ColoredVertex2d(end, color));
	}

	void putPoint(vec2 pos, Color4ub color)
	{
		pointBuffer.put(ColoredVertex2d(pos, color));
	}

	void reset()
	{
		triBuffer.clear();
		lineBuffer.clear();
		pointBuffer.clear();
	}
}
