/**
Copyright: Copyright (c) 2014-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.storage.regionstorage;

import std.experimental.logger;
import std.array : Appender;
import std.file : exists, mkdirRecurse;
import std.format : formattedWrite;
import std.path : isValidPath, dirSeparator;
import std.stdio : FOPEN_MAX;

import dlib.math.vector : ivec3;
import voxelman.config : TimestampType;
import voxelman.storage.chunk;
import voxelman.storage.region : Region, REGION_SIZE, ChunkStoreInfo, calcChunkIndex;
import voxelman.storage.utils;

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

	public TimestampType chunkTimestamp(ivec3 chunkPos)
	{
		ivec3 regionPos = calcRegionPos(chunkPos);
		ivec3 localChunkCoords = calcRegionLocalPos(chunkPos);

		if (!isRegionOnDisk(regionPos))
			return 0;

		return loadRegion(regionPos).chunkTimestamp(localChunkCoords);
	}

	public ChunkStoreInfo getChunkStoreInfo(ivec3 chunkPos)
	{
		ivec3 regionPos = calcRegionPos(chunkPos);
		ivec3 localChunkCoords = calcRegionLocalPos(chunkPos);

		if (!isRegionOnDisk(regionPos))
		{
			return ChunkStoreInfo(false, localChunkCoords, chunkPos,
				regionPos, calcChunkIndex(localChunkCoords));
		}

		auto res = loadRegion(regionPos).getChunkStoreInfo(localChunkCoords);
		res.positionInWorld = chunkPos;
		res.parentRegionPosition = regionPos;
		return res;
	}

	bool isRegionOnDisk(ivec3 regionPos)
	{
		if (getRegion(regionPos) !is null)
			return true;
		return exists(regionFilename(regionPos));
	}

	ubyte[] readChunk(ivec3 chunkPos, ubyte[] outBuffer, out TimestampType timestamp)
	{
		ivec3 regionPos = calcRegionPos(chunkPos);
		ivec3 localChunkCoords = calcRegionLocalPos(chunkPos);

		Region* region = loadRegion(regionPos);
		return region.readChunk(localChunkCoords, outBuffer, timestamp);
	}

	void writeChunk(ivec3 chunkPos, in ubyte[] blockData, TimestampType timestamp)
	{
		ivec3 regionPos = calcRegionPos(chunkPos);
		ivec3 localChunkCoords = calcRegionLocalPos(chunkPos);

		Region* region = loadRegion(regionPos);
		region.writeChunk(localChunkCoords, blockData, timestamp);
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
		return regions.get(regionPos, null);
	}

	private const(char[]) regionFilename(ivec3 regionPos)
	{
		appender.clear();
		formattedWrite(appender, "%s%s%s_%s_%s.region",
			regionDirectory, dirSeparator, regionPos.x, regionPos.y, regionPos.z);
		return appender.data;
	}
}
