/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module mc_region;

import std.algorithm;
import std.bitmanip;
import std.file;
import std.getopt;
import std.path;
import std.stdio;

import voxelman.math;
import voxelman.core.config;
import voxelman.math.box;

enum regionExt = ".mca";
enum MC_REGION_WIDTH = 32;
enum MC_REGION_WIDTH_SQR = MC_REGION_WIDTH * MC_REGION_WIDTH;
enum MC_CHUNK_WIDTH = 16;
enum MC_CHUNK_WIDTH_SQR = MC_CHUNK_WIDTH * MC_CHUNK_WIDTH;
enum MC_CHUNK_WIDTH_CUBE = MC_CHUNK_WIDTH * MC_CHUNK_WIDTH * MC_CHUNK_WIDTH;
enum MC_CHUNK_HEIGHT = 256;
enum CHUNKS_PER_MC_REGION_WIDTH = MC_CHUNK_WIDTH * MC_REGION_WIDTH / CHUNK_SIZE;
enum CHUNKS_PER_MC_REGION_HEIGHT = MC_CHUNK_HEIGHT / CHUNK_SIZE;

enum SECTOR_SIZE = 4096;
enum McChunkCompression : ubyte {
	gzip = 1,
	zlib
}

Box calcRegionBox(int rx, int rz)
{
	int x = rx * CHUNKS_PER_MC_REGION_WIDTH;
	int y = 0;
	int z = rz * CHUNKS_PER_MC_REGION_WIDTH;
	int sx = CHUNKS_PER_MC_REGION_WIDTH;
	int sy = CHUNKS_PER_MC_REGION_HEIGHT;
	int sz = CHUNKS_PER_MC_REGION_WIDTH;
	return Box(ivec3(x, y, z), ivec3(sx, sy, sz));
}

auto regionIterator(string regionDir)
{
	return dirEntries(regionDir, SpanMode.shallow)
		.filter!(entry => entry.isFile && extension(entry.name) == regionExt);
}

struct McRegion
{
	ubyte[] buffer;
	uint[MC_REGION_WIDTH_SQR] offsets;
	uint[MC_REGION_WIDTH_SQR] timestamps;
	string path;
	int x, z;

	/// iterates all chunks in region.
	int opApply(scope int delegate(McChunkInfo) del)
	{
		File file;
		file.open(path);
		readHeader(file);

		foreach(chunkIndex; 0..MC_REGION_WIDTH_SQR)
		{
			if (offsets[chunkIndex] == 0)
				continue;

			int x = chunkIndex % MC_REGION_WIDTH;
			int z = chunkIndex / MC_REGION_WIDTH;

			auto offset = offsets[chunkIndex];
			auto sectorNumber = offset >> 8;
			auto numSectors = offset & 0xFF;

			file.seek(sectorNumber * SECTOR_SIZE);
			ubyte[4] uintBuffer;
			file.rawRead(uintBuffer[]);
			auto dataLength = bigEndianToNative!uint(uintBuffer);
			ubyte[1] compressionType;
			file.rawRead(compressionType);

			if (dataLength > numSectors * SECTOR_SIZE) {
				writefln("Invalid data length (%s, %s), data length (%s) > num sectors (%s) * %s",
					x, z, dataLength, numSectors, SECTOR_SIZE);
				continue;
			}

			ubyte[] data = file.rawRead(buffer[0..dataLength-1]);

			auto chunkInfo = McChunkInfo(x, z, data);

			if (compressionType[0] == McChunkCompression.gzip) {
				writefln("gzip, skipping");
				continue;
			}
			else if (compressionType[0] == McChunkCompression.zlib)
			{
				import std.zlib;
				chunkInfo.data = cast(ubyte[])uncompress(data);
			}

			if (auto ret = del(chunkInfo))
				return ret;
		}
		return 0;
	}

	void parseRegionFilename(string regionFile)
	{
		import std.regex : matchFirst, ctRegex;
		import std.conv : to;
		enum regionPattern = `r\.([-]?[0-9]+)\.([-]?[0-9]+)`;

		path = regionFile;
		string name = regionFile.baseName.stripExtension;
		auto c = matchFirst(name, ctRegex!(regionPattern, "m"));
		x = to!int(c[1]);
		z = to!int(c[2]);
	}

	void readHeader(ref File file)
	{
		file.rawRead(offsets[]);
		file.rawRead(timestamps[]);

		version(LittleEndian)
		foreach(i; 0..MC_REGION_WIDTH_SQR)
		{
			offsets[i] = bigEndianToNative!uint(*cast(ubyte[4]*)&offsets[i]);
			timestamps[i] = bigEndianToNative!uint(*cast(ubyte[4]*)&timestamps[i]);
		}
	}
}

struct McChunkInfo
{
	int x, z;
	ubyte[] data;
}
