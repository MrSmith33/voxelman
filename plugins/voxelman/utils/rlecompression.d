/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.utils.rlecompression;

import std.range : put;

ubyte[] rleEncode(in ubyte[] data, ubyte[] outBuffer)
{
	if (data.length == 0) return null;

	ubyte[] original = outBuffer;
	ubyte count = 1;
	ubyte current = data[0];

	foreach(item; data[1..$])
	{
		if (current == item && count < ubyte.max)
		{
			++count;
		}
		else
		{
			put(outBuffer, count);
			put(outBuffer, current);
			count = 1;
			current = item;
		}
	}
	put(outBuffer, count);
	put(outBuffer, current);

	return original[0..$-outBuffer.length];
}

ubyte[] rleDecode(in ubyte[] data, ubyte[] outBuffer)
{
	if (data.length == 0) return null;

	assert(data.length % 2 == 0);
	ubyte[] original = outBuffer;

	foreach(i; 0..data.length/2)
	{
		ubyte count = data[i*2];
		ubyte item = data[i*2 + 1];

		outBuffer[0..count] = item;
		outBuffer = outBuffer[count..$];
	}

	return original[0..$-outBuffer.length];
}

unittest
{
	ubyte[32] data = [0,0,0,0,0,1,1,1,1,2,2,2,2,0,0,0,0,0,1,0,4,0,1,0,0,0,0,0,0,0,0,1];
	ubyte[32] outBuffer;
	assert(rleEncode(data, outBuffer) == [5,0,4,1,4,2,5,0,1,1,1,0,1,4,1,0,1,1,8,0,1,1]);
	assert(rleDecode(rleEncode(data, outBuffer).dup, outBuffer) == data);
}
