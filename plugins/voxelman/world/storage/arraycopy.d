/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.arraycopy;

import voxelman.math;

/// writes source to a box within dest
void setSubArray(T)(
	T[] dest,
	ivec3 destSize,  // 7x8x9
	ivec3 destPos,
	T[] source,
	ivec3 sourceSize, // 4x5x6
	Box sourceBox, // (1,2,3) 2x3x4
	) @nogc
{
	assert(dest.length == destSize.x * destSize.y * destSize.z);
	assert(source.length == sourceSize.x * sourceSize.y * sourceSize.z);

	const auto dest_size_y = destSize.x * destSize.z; // 1 y slice
	const auto source_size_y = sourceSize.x * sourceSize.z; // 1 y slice

	foreach(y; 0..sourceBox.size.y)
	foreach(z; 0..sourceBox.size.z)
	{
		auto destY = y + destPos.y;
		auto destZ = z + destPos.z;
		auto fromDest = destY * dest_size_y + destZ * destSize.x + destPos.x;
		auto toDest = fromDest + sourceBox.size.x;

		auto sourceY = y + sourceBox.position.y;
		auto sourceZ = z + sourceBox.position.z;
		auto fromSource = sourceY * source_size_y + sourceZ * sourceSize.x + sourceBox.position.x;
		auto toSource = fromSource + sourceBox.size.x;

		dest[fromDest..toDest] = source[fromSource..toSource];
	}
}

/// writes full source to a box within dest
void setSubArray(T)(T[] dest, ivec3 destSize, Box box, T[] source) @nogc
{
	const int dest_size_y = destSize.x * destSize.z; // 1 y slice
	assert(dest.length == dest_size_y * destSize.y);
	assert(source.length == box.volume);

	if (box.position.x == 0 && box.size.x == destSize.x)
	{
		if (box.position.z == 0 && box.size.z == destSize.z)
		{
			if (box.position.y == 0 && box.size.y == destSize.y)
			{
				dest[] = source;
			}
			else
			{
				auto from = box.position.y * dest_size_y;
				auto to = (box.position.y + box.size.y) * dest_size_y;
				dest[from..to] = source;
			}
		}
		else
		{
			auto box_size_sqr = box.size.x * box.size.z;
			foreach(y; box.position.y..(box.position.y + box.size.y))
			{
				auto fromDest = y * dest_size_y + box.position.z * destSize.x;
				auto toDest = y * dest_size_y + (box.position.z + box.size.z) * destSize.x;
				auto sourceY = y - box.position.y;
				auto fromSource = sourceY * box_size_sqr + box.size.z;
				auto toSource = sourceY * box_size_sqr + box.position.z * box.size.z;
				dest[fromDest..toDest] = source[fromSource..toSource];
			}
		}
	}
	else
	{
		int posx = box.position.x;
		int endx = box.position.x + box.size.x;
		int endy = box.position.y + box.size.y;
		int endz = box.position.z + box.size.z;
		auto box_size_sqr = box.size.x * box.size.z;

		foreach(y; box.position.y..endy)
		foreach(z; box.position.z..endz)
		{
			auto fromDest = y * dest_size_y + z * destSize.x + box.position.x;
			auto toDest = fromDest + box.size.x;
			auto sourceY = y - box.position.y;
			auto sourceZ = z - box.position.z;
			auto fromSource = sourceY * box_size_sqr + sourceZ * box.size.x;
			auto toSource = fromSource + box.size.x;

			dest[fromDest..toDest] = source[fromSource..toSource];
		}
	}
}

void setSubArray(T)(T[] dest, ivec3 destSize, Box box, T item) @nogc
{
	const int dest_size_y = destSize.x * destSize.z; // 1 y slice
	assert(dest.length == destSize.x * destSize.y * destSize.z);

	if (box.position.x == 0 && box.size.x == destSize.x)
	{
		if (box.position.z == 0 && box.size.z == destSize.z)
		{
			if (box.position.y == 0 && box.size.y == destSize.y)
			{
				dest[] = item;
			}
			else
			{
				auto from = box.position.y * dest_size_y;
				auto to = (box.position.y + box.size.y) * dest_size_y;
				dest[from..to] = item;
			}
		}
		else
		{
			foreach(y; box.position.y..(box.position.y + box.size.y))
			{
				auto from = y * dest_size_y + box.position.z * destSize.x;
				auto to = y * dest_size_y + (box.position.z + box.size.z) * destSize.x;
				dest[from..to] = item;
			}
		}
	}
	else
	{
		int endy = box.position.y + box.size.y;
		int endz = box.position.z + box.size.z;
		foreach(y; box.position.y..endy)
		foreach(z; box.position.z..endz)
		{
			auto from = y * dest_size_y + z * destSize.x + box.position.x;
			auto to = from + box.size.x;
			dest[from..to] = item;
		}
	}
}
