/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.utils.compression;

import voxelman.log;

extern(C) nothrow {
	int LZ4_compress_default(const ubyte* source, ubyte* dest, int sourceSize, int maxDestSize);
	int LZ4_decompress_safe(const ubyte* source, ubyte* dest, int compressedSize, int maxDecompressedSize);
}

ubyte[] compress(in ubyte[] data, ubyte[] outBuffer)
{
	int res = LZ4_compress_default(data.ptr, outBuffer.ptr, cast(int)data.length, cast(int)outBuffer.length);
	return outBuffer[0..res];
}
ubyte[] decompress(in ubyte[] data, ubyte[] outBuffer)
{
	int res = LZ4_decompress_safe(data.ptr, outBuffer.ptr, cast(int)data.length, cast(int)outBuffer.length);
	if (res < 0)
	{
		errorf("decompress failed with result %s in %s buf %s", res, data.length, outBuffer.length);
		return null;
	}
	return outBuffer[0..res];
}
