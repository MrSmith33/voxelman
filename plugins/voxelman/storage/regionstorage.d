/**
Copyright: Copyright (c) 2014-2016 Andrey Penechko.
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
import voxelman.core.config : TimestampType;
import voxelman.storage.chunk;
import voxelman.storage.coordinates;
import voxelman.storage.region : Region, REGION_SIZE, ChunkStoreInfo;
import voxelman.storage.utils;

enum MAX_CACHED_REGIONS = FOPEN_MAX;

/// Used for easy saving/loading chunks into region files.
struct RegionStorage
{
	private string regionDirectory;
	private Region*[RegionWorldPos] regions;
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

	bool isChunkOnDisk(ChunkWorldPos chunkPos)
	{
		RegionWorldPos regionPos = RegionWorldPos(chunkPos);
		ChunkRegionPos localChunkPositions = ChunkRegionPos(chunkPos);

		if (!isRegionOnDisk(regionPos))
			return false;

		return loadRegion(regionPos).isChunkOnDisk(localChunkPositions);
	}

	public TimestampType chunkTimestamp(ChunkWorldPos chunkPos)
	{
		RegionWorldPos regionPos = RegionWorldPos(chunkPos);
		ChunkRegionPos localChunkPositions = ChunkRegionPos(chunkPos);

		if (!isRegionOnDisk(regionPos))
			return 0;

		return loadRegion(regionPos).chunkTimestamp(localChunkPositions);
	}

	public ChunkStoreInfo getChunkStoreInfo(ChunkWorldPos chunkPos)
	{
		RegionWorldPos regionPos = RegionWorldPos(chunkPos);
		ChunkRegionPos localChunkPositions = ChunkRegionPos(chunkPos);

		if (!isRegionOnDisk(regionPos))
		{
			return ChunkStoreInfo(false, localChunkPositions, chunkPos,
				regionPos, ChunkRegionIndex(localChunkPositions));
		}

		auto res = loadRegion(regionPos).getChunkStoreInfo(localChunkPositions);
		res.positionInWorld = chunkPos;
		res.parentRegionPosition = regionPos;
		return res;
	}

	bool isRegionOnDisk(RegionWorldPos regionPos)
	{
		if (getRegion(regionPos) !is null)
			return true;
		return exists(regionFilename(regionPos));
	}

	ubyte[] readChunk(ChunkWorldPos chunkPos, ubyte[] outBuffer, out TimestampType timestamp)
	{
		RegionWorldPos regionPos = RegionWorldPos(chunkPos);
		ChunkRegionPos localChunkPositions = ChunkRegionPos(chunkPos);

		Region* region = loadRegion(regionPos);
		return region.readChunk(localChunkPositions, outBuffer, timestamp);
	}

	void writeChunk(ChunkWorldPos chunkPos, in ubyte[] blockData, TimestampType timestamp)
	{
		RegionWorldPos regionPos = RegionWorldPos(chunkPos);
		ChunkRegionPos localChunkPositions = ChunkRegionPos(chunkPos);

		Region* region = loadRegion(regionPos);
		region.writeChunk(localChunkPositions, blockData, timestamp);
	}

	private Region* loadRegion(RegionWorldPos regionPos)
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

	private Region* getRegion(RegionWorldPos regionPos)
	{
		return regions.get(regionPos, null);
	}

	private const(char[]) regionFilename(RegionWorldPos regionPos)
	{
		appender.clear();
		formattedWrite(appender, "%s%s%s_%s_%s.region",
			regionDirectory, dirSeparator, regionPos.x, regionPos.y, regionPos.z);
		return appender.data;
	}
}
