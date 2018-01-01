/**
Copyright: Copyright (c) 2017-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.container.fixedbuffer;

struct FixedBuffer(T, size_t buf_size)
{
	T[buf_size] buf;
	private MinTypeForLength!buf_size length;

	T opIndex(size_t index) {
		return data[index];
	}

	void put(T item) {
		buf[length] = item;
		++length;
	}

	T[] data() {
		return buf[0..length];
	}

	void clear() nothrow {
		length = 0;
	}

	enum capacity = buf_size;
}

template MinTypeForLength(size_t value)
{
	static if (value <= ubyte.max)
		alias MinTypeForLength = ubyte;
	else static if (value <= ushort.max)
		alias MinTypeForLength = ushort;
	else static if (value <= uint.max)
		alias MinTypeForLength = uint;
	else static if (value <= size_t.max)
		alias MinTypeForLength = size_t;
}
