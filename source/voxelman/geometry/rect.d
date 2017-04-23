/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.geometry.rect;

import voxelman.math;

struct frect
{
	this (float x, float y, float width, float height) {
		this.position = vec2(x, y);
		this.size = vec2(width, height);
	}

	this (T1, T2)(T1 position, T2 size) {
		this.position = position;
		this.size = size;
	}

	this (irect rect) {
		this.position = rect.position;
		this.size = rect.size;
	}

	vec2 position = vec2(0, 0);
	vec2 size = vec2(0, 0);

	float area() @property const @nogc
	{
		return size.x * size.y;
	}

	vec2 endPosition() @property const
	{
		return position + size;
	}

	bool empty() const @property
	{
		return size.x == 0 && size.y == 0;
	}

	bool contains(vec2 point) const
	{
		if (point.x < position.x || point.x >= position.x + size.x) return false;
		if (point.y < position.y || point.y >= position.y + size.y) return false;
		return true;
	}
}

struct irect
{
	this (ivec2 position, ivec2 size) {
		this.position = position;
		this.size = size;
	}

	this (int x, int y, int width, int height) {
		this.x = x;
		this.y = y;
		this.width = width;
		this.height = height;
	}

	union {
		ivec2 position;
		struct { int x, y; }
	}
	union {
		ivec2 size;
		struct { int width, height; }
	}

	int area() @property const @nogc
	{
		return width * height;
	}

	ivec2 endPosition() @property const
	{
		return position + size - ivec2(1,1);
	}

	bool empty() const @property
	{
		return width == 0 && height == 0;
	}

	bool contains(ivec2 point) const
	{
		if (point.x < x || point.x >= x + width) return false;
		if (point.y < y || point.y >= y + height) return false;
		return true;
	}

	/// Adds a point to a rectangle.
	/// This results in the smallest rectangle that contains both the rectangle and the point.
	void add(ivec2 point)
	{
		if (point.x < x)
		{
			immutable int diff_x = x - point.x;
			width += diff_x;
			x -= diff_x;
		}
		else if(point.x > x + width - 1)
		{
			immutable int diff_x = point.x - (x + width - 1);
			width += diff_x;
		}

		if (point.y < y)
		{
			immutable int diff_y = y - point.y;
			height += diff_y;
			y -= diff_y;
		}
		else if(point.y > y + height - 1)
		{
			immutable int diff_y = point.y - (y + height - 1);
			height += diff_y;
		}
	}

	void toString()(scope void delegate(const(char)[]) sink) const
	{
		import std.format : formattedWrite;
		sink.formattedWrite("irect(pos %s, %s size %s, %s)", x, y, width, height);
	}
}
