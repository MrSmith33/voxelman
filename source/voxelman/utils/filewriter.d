/**
Copyright: Copyright (c) 2016-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.utils.filewriter;

import std.stdio : File;

struct FileWriter
{
	File file;

	enum CAPACITY = 4096;
	ubyte[CAPACITY] buffer;
	size_t length;

	void put(ubyte[] data ...)
	{
		size_t cap = capacity;
		if (data.length > cap)
		{
			size_t writeOffset;

			// fill buffer till CAPACITY
			if (length > 0)
			{
				buffer[length..$] = data[0..cap];
				file.rawWrite(buffer);
				writeOffset = cap;
			}

			size_t writeLength = ((data.length - writeOffset) / CAPACITY) * CAPACITY;
			size_t writeTo = writeOffset+writeLength;
			if (writeLength)
				file.rawWrite(data[writeOffset..writeTo]);

			size_t writeLater = data.length - writeTo;
			if (writeLater)
			{
				buffer[0..writeLater] = data[writeTo..$];
				length = writeLater;
			}
			else
			{
				length = 0;
			}
		}
		else
		{
			buffer[length..length+data.length] = data;
			length += data.length;
		}
	}

	void flush() {
		if (length) {
			file.rawWrite(buffer[0..length]);
			length = 0;
		}
	}

	size_t capacity() { return CAPACITY - length; }
}
