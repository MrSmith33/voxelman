/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.regionstorage;

import std.array : Appender;
import std.file : exists, mkdirRecurse;
import std.format : formattedWrite;
import std.path : isValidPath, dirSeparator;
import std.stdio : writef, writeln, writefln, FOPEN_MAX;

import dlib.math.vector : ivec3;
import voxelman.region : Region, REGION_SIZE;

enum MAX_CACHED_REGIONS = FOPEN_MAX;

/// Used for easy saving/loading chunks into region files.
struct RegionStorage
{
	private string regionDirectory;
	private Region*[ivec3] regions;
	private char[] buffer;
	private Appender!(char[]) appender;

	@disable this();
	this(string regionDir)
	{
		assert(isValidPath(regionDir));

		regionDirectory = regionDir;
		if (!exists(regionDirectory))
			mkdirRecurse(regionDirectory);

		buffer = new char[1024];
		appender = Appender!(char[])(buffer);
	}

	void clear()
	{
		foreach(Region* region; regions.byValue)
			region.close();

		regions = null;
	}

	bool isChunkOnDisk(ivec3 chunkPos)
	{
		ivec3 regionPos = calcRegionPos(chunkPos);
		ivec3 localChunkCoords = calcRegionLocalPos(chunkPos);
		
		if (!isRegionOnDisk(regionPos)) 
			return false;

		return loadRegion(regionPos).isChunkOnDisk(localChunkCoords);
	}

	bool isRegionOnDisk(ivec3 regionPos)
	{
		if (getRegion(regionPos) !is null)
			return true;
		return exists(regionFilename(regionPos));
	}

	ubyte[] readChunk(ivec3 chunkPos, ubyte[] outBuffer)
	{
		ivec3 regionPos = calcRegionPos(chunkPos);
		ivec3 localChunkCoords = calcRegionLocalPos(chunkPos);

		Region* region = loadRegion(regionPos);
		return region.readChunk(localChunkCoords, outBuffer);
	}

	void writeChunk(ivec3 chunkPos, in ubyte[] chunkData)
	{
		ivec3 regionPos = calcRegionPos(chunkPos);
		ivec3 localChunkCoords = calcRegionLocalPos(chunkPos);

		Region* region = loadRegion(regionPos);
		region.writeChunk(localChunkCoords, chunkData);
	}

	private Region* loadRegion(ivec3 regionPos)
	{
		if (auto region = getRegion(regionPos))
			return region;

		if (regions.length >= MAX_CACHED_REGIONS)
			clear();

		string filename = regionFilename(regionPos).idup;
		assert(isValidPath(filename));
		
		Region* region = new Region(filename);
		regions[regionPos] = region;
		return region;
	}

	private Region* getRegion(ivec3 regionPos)
	{
		Region** region = regionPos in regions;
		if (region is null) return null;
		assert(*region);
		return *region;
	}

	private const(char[]) regionFilename(ivec3 regionPos)
	{
		appender.clear();
		formattedWrite(appender, "%s%s%s_%s_%s.region",
			regionDirectory, dirSeparator, regionPos.x, regionPos.y, regionPos.z);
		return appender.data;
	}

	private ivec3 calcRegionPos(ivec3 chunkPos)
	{
		import std.math : floor;
		return ivec3(
			cast(int)floor(chunkPos.x / cast(float)REGION_SIZE),
			cast(int)floor(chunkPos.y / cast(float)REGION_SIZE),
			cast(int)floor(chunkPos.z / cast(float)REGION_SIZE));
	}

	private ivec3 calcRegionLocalPos(ivec3 chunkWorldPos)
	{
		chunkWorldPos.x %= REGION_SIZE;
		chunkWorldPos.y %= REGION_SIZE;
		chunkWorldPos.z %= REGION_SIZE;
		if (chunkWorldPos.x < 0) chunkWorldPos.x += REGION_SIZE;
		if (chunkWorldPos.y < 0) chunkWorldPos.y += REGION_SIZE;
		if (chunkWorldPos.z < 0) chunkWorldPos.z += REGION_SIZE;
		return chunkWorldPos;
	}
}