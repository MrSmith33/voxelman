/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.algorithm.arraycopy2d;

import voxelman.math;

/// writes source subrect to a dest subrect
void setSubArray2d(T)(
	in T[] source, in ivec2 sourceSize, in irect sourceSubRect,
	T[] dest, in ivec2 destSize, in ivec2 destSubRectPos) @nogc
{
	if (sourceSize.x == sourceSubRect.width && sourceSize.x == destSize.x)
	{
		assert(sourceSubRect.x == 0);
		assert(destSubRectPos.x == 0);

		auto rectArea = sourceSubRect.width * sourceSubRect.height;

		auto fromSource = sourceSubRect.y * sourceSize.x;
		auto toSource = fromSource + rectArea;

		auto fromDest = destSubRectPos.y * destSize.x;
		auto toDest = fromDest + rectArea;

		dest[fromDest..toDest] = source[fromSource..toSource];
	}
	else
	{
		foreach(y; 0..sourceSubRect.height)
		{
			auto fromSource = (sourceSubRect.y + y) * sourceSize.x + sourceSubRect.x;
			auto toSource = fromSource + sourceSubRect.width;

			auto fromDest = (destSubRectPos.y + y) * destSize.x + destSubRectPos.x;
			auto toDest = fromDest + sourceSubRect.width;

			dest[fromDest..toDest] = source[fromSource..toSource];
		}
	}
}

// fill dest sub rect with item
void setSubArray2d(T)(T item, T[] dest, ivec2 destSize, irect destSubRect) @nogc
{
	if (destSize.x == destSubRect.width)
	{
		assert(destSubRect.x == 0);

		auto fromDest = destSubRect.y * destSize.x;
		auto toDest = fromDest + destSubRect.area;

		dest[fromDest..toDest] = item;
	}
	else
	{
		foreach(y; 0..destSubRect.height)
		{
			auto fromDest = (destSubRect.y + y) * destSize.x + destSubRect.x;
			auto toDest = fromDest + destSubRect.width;

			dest[fromDest..toDest] = item;
		}
	}
}
