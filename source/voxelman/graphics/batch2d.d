/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
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

enum CommandType {
	batch,
	clipRect
}

struct Command
{
	this(Texture texture, size_t numVertices) {
		type = CommandType.batch;
		this.texture = texture;
		this.numVertices = numVertices;
	}
	this(irect clipRect) {
		type = CommandType.clipRect;
		this.clipRect = clipRect;
	}
	CommandType type;
	union
	{
		struct // CommandType.batch
		{
			Texture texture;
			size_t numVertices;
		}
		struct // CommandType.clipRect
		{
			irect clipRect;
		}
	}
}

struct BatchRenderCommand
{
	Texture texture;
	size_t numVertices;
}

struct ClipRectCommand
{
	irect rect;
}

import voxelman.model.vertex;
alias UvColVertex2d = VertexPosUvColor!(float, 3, float, 2, ubyte, 4);
struct TexturedBatch2d
{
	Buffer!UvColVertex2d buffer;
	Buffer!Command commands;
	Buffer!irect rectStack;
	private bool isCurrentClipRectEmpty;

	void putRect(frect target, frect source, float depth, Color4ub color, Texture tex)
	{
		auto pos0 = vec3(target.position.x, target.position.y, depth);
		auto pos1 = vec3(target.position.x, target.position.y + target.size.y, depth);
		auto pos2 = vec3(target.position.x + target.size.x, target.position.y + target.size.y, depth);
		auto pos3 = vec3(target.position.x + target.size.x, target.position.y, depth);

		auto tex0 = source.position;
		auto tex1 = vec2(source.position.x, source.position.y + source.size.y);
		auto tex2 = vec2(source.position.x + source.size.x, source.position.y + source.size.y);
		auto tex3 = vec2(source.position.x + source.size.x, source.position.y);

		auto vert0 = UvColVertex2d(pos0, tex0, color);
		auto vert1 = UvColVertex2d(pos1, tex1, color);
		auto vert2 = UvColVertex2d(pos2, tex2, color);
		auto vert3 = UvColVertex2d(pos3, tex3, color);

		buffer.put(vert0, vert3, vert1, vert1, vert2, vert3);
		putNVerticies(6, tex);
	}

	void addOffsetToLastRects(vec2 offset, size_t numLastRects)
	{
		addOffsetToLastVerticies(offset, numLastRects * 6);
	}

	void addOffsetToLastVerticies(vec2 offset, size_t numLastVerticies)
	{
		vec3 effectiveOffset = vec3(offset.x, offset.y, 0);
		foreach (ref vert; buffer.data[$-numLastVerticies..$])
		{
			vert.position += effectiveOffset;
		}
	}

	void pushClipRect(irect rect)
	{
		rectStack.put(rect);
		if (!rectStack.empty)
		{
			rect = rectIntersection(rect, rectStack.back);
		}
		setClipRect(rect);
	}

	void popClipRect()
	{
		// there must be always rect in the stack since we pushed one after reset
		rectStack.unput(1);
		irect rect = rectStack.data[$-1];
		setClipRect(rect);
	}

	void setClipRect(irect rect)
	{
		assert(rect.width >= 0, "width is negative");
		assert(rect.height >= 0, "height is negative");
		isCurrentClipRectEmpty = rect.empty;
		if (commands.data.length)
		{
			Command* command = &commands.data[$-1];

			// replace clip rect of last command if it sets clip rect
			if (command.type == CommandType.clipRect)
			{
				command.clipRect = rect;
				return;
			}
		}
		commands.put(Command(rect));
	}

	private void putNVerticies(size_t verticies, Texture tex)
	{
		if (isCurrentClipRectEmpty) return;
		if (commands.data.length)
		{
			Command* command = &commands.data[$-1];

			// append vertices to the last command if texture is teh same
			if (command.type == CommandType.batch && command.texture == tex)
			{
				command.numVertices += verticies;
				return;
			}
		}
		commands.put(Command(tex, verticies));
	}

	void reset(irect initialClipRect)
	{
		buffer.clear();
		commands.clear();
		rectStack.clear();
		pushClipRect(initialClipRect);
	}
}
