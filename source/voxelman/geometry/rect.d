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

RectT rectIntersection(RectT)(const RectT a, const RectT b)
{
	typeof(RectT.size.x)[2] xIntersection = intersection(a.position.x, a.position.x + a.size.x, b.position.x, b.position.x + b.size.x);
	typeof(RectT.size.x)[2] yIntersection = intersection(a.position.y, a.position.y + a.size.y, b.position.y, b.position.y + b.size.y);
	if (xIntersection[0] > xIntersection[1]) return RectT();
	if (yIntersection[0] > yIntersection[1]) return RectT();

	return RectT(xIntersection[0], yIntersection[0], xIntersection[1] - xIntersection[0], yIntersection[1] - yIntersection[0]);
}

T[2] intersection(T)(const T aStart, const T aEnd, const T bStart, const T bEnd)
	if (is(T == int) || is(T == float))
{
	T[2] res;

	if (aStart < bStart)
	{
		res[0] = bStart;
	}
	else if (aStart > bStart)
	{
		res[0] = aStart;
	}
	else
	{
		res[0] = aStart;
	}

	if (aEnd < bEnd)
	{
		res[1] = aEnd;
	}
	else if (aEnd > bEnd)
	{
		res[1] = bEnd;
	}
	else
	{
		res[1] = bEnd;
	}

	return res;
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
		sink.formattedWrite("irect(x %s y %s w %s h %s)", x, y, width, height);
	}
}
