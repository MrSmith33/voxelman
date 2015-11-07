/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.storage.world;

import std.experimental.logger;
import std.file : readFile = read, writeFile = write, exists, mkdirRecurse, isValidPath;
import std.path : absolutePath, buildPath, buildNormalizedPath;

import cbor;
import dlib.math.vector;

import voxelman.config;
import voxelman.storage.chunkprovider;
import voxelman.storage.chunkstorage;
import voxelman.storage.worldaccess;

struct WorldInfo
{
	string name = DEFAULT_WORLD_NAME;
	TimestampType simulationTick;
	ivec3 spawnPosition;
	//block mapping
}

private ubyte[1024] buffer;

struct World
{
	WorldInfo worldInfo;

	string worldDirectory;
	string worldInfoFilename = WORLD_FILE_NAME;

	void init(string worldDir)
	{
		assert(isValidPath(worldDir));

		worldDirectory = worldDir.absolutePath.buildNormalizedPath;
		worldInfoFilename = buildPath(worldDirectory, WORLD_FILE_NAME);
	}

	TimestampType currentTimestamp() @property
	{
		return worldInfo.simulationTick;
	}

	void update()
	{
		++worldInfo.simulationTick;
	}

	void save()
	{
		writeWorldInfo();
		infof("saved world '%s'", worldInfoFilename);
	}

	void load()
	{
		if (!exists(worldDirectory))
		{
			mkdirRecurse(worldDirectory);
		}

		if (!exists(worldInfoFilename))
		{
			writeWorldInfo();
			return;
		}

		readWorldInfo();
		infof("loaded world %s %s", worldInfoFilename, worldInfo);
	}

	private void readWorldInfo()
	{
		ubyte[] data = cast(ubyte[])readFile(worldInfoFilename, 1024);
		worldInfo = decodeCborSingleDup!WorldInfo(data);
	}

	private void writeWorldInfo()
	{
		ubyte[] bufferTemp = buffer;
		size_t size = encodeCbor(bufferTemp[], worldInfo);
		writeFile(worldInfoFilename, bufferTemp[0..size]);
	}
}
