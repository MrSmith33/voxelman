/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.math.offset4;

alias margins4 = offset4;
alias borders4 = offset4;
alias padding4 = offset4;

/// Used to set size of borders, padding, margins, spacing etc
struct offset4
{
	union
	{
		struct
		{
			int left;
			int right;
			int top;
			int bottom;
		}
		int[4] arrayof;
	}

	void toString()(scope void delegate(const(char)[]) sink) const
	{
		import std.string : formattedWrite;
		return formattedWrite(sink, "offset4(%s, %s, %s, %s)", left, right, top, bottom);
	}

	this(int off)
	{
		arrayof[] = off;
	}

	this(int[4] array)
	{
		arrayof = array;
	}

	this(int l, int r, int t, int b)
	{
		left = l;
		right = r;
		top = t;
		bottom = b;
	}

	this(int hor, int vert)
	{
		left = hor;
		right = hor;
		top = vert;
		bottom = vert;
	}

	int hori() const @property nothrow @nogc
	{
		return left + right;
	}

	int vert() const @property nothrow @nogc
	{
		return top + bottom;
	}
}
