/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.geometry.rect;

//import std.algorithm : alg_min = min, alg_max = max;
import voxelman.math;

struct Rect
{
	ivec2 position;
	ivec2 size;

	int area() @property const @nogc
	{
		return size.x * size.y;
	}

	ivec2 endPosition() @property const
	{
		return position + size - ivec2(1,1);
	}

	bool empty() const @property
	{
		return size.x == 0 && size.y == 0;
	}

	bool contains(ivec2 point) const
	{
		if (point.x < position.x || point.x >= position.x + size.x) return false;
		if (point.y < position.y || point.y >= position.y + size.y) return false;
		return true;
	}

	/// Adds a point to a rectangle.
	/// This results in the smallest rectangle that contains both the rectangle and the point.
	void add(ivec2 point)
	{
		if (point.x < position.x)
		{
			immutable int diff_x = position.x - point.x;
			size.x += diff_x;
			position.x -= diff_x;
		}
		else if(point.x > position.x + size.x - 1)
		{
			immutable int diff_x = point.x - (position.x + size.x - 1);
			size.x += diff_x;
		}

		if (point.y < position.y)
		{
			immutable int diff_y = position.y - point.y;
			size.y += diff_y;
			position.y -= diff_y;
		}
		else if(point.y > position.y + size.y - 1)
		{
			immutable int diff_y = point.y - (position.y + size.y - 1);
			size.y += diff_y;
		}
	}
}
