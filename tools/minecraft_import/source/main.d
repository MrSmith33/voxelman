/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module main;

import std.algorithm;
import std.file;
import std.getopt;
import std.path;
import std.stdio;

import voxelman.math;
import voxelman.core.config;
import voxelman.block.utils : BlockInfoTable;
import voxelman.world.storage.chunkmanager : ChunkManager, WriteBufferPolicy;
import voxelman.world.storage.chunkprovider;
import voxelman.world.storage.chunkobservermanager : ChunkObserverManager;
import voxelman.world.worlddb : WorldDb;
import voxelman.geometry.box;
import voxelman.world.storage.worldbox;
import voxelman.world.storage.chunk;
import voxelman.world.storage.coordinates;
import voxelman.world.gen.utils;

import mc_region;
import nbt;

enum worldExtension = ".db";

unittest
{
	enum SIZE = 32;
	enum SIZE_SQR = SIZE * SIZE;
	enum SIZE_CUBE = SIZE * SIZE * SIZE;
	ubyte[SIZE_CUBE] dest;
	ubyte[8] source;
	source[] = 1;
	Box box = Box(ivec3(2,2,2), ivec3(2,2,2));
	setSubArray(dest, box, source);
	foreach(y; 0..5) {
		foreach(z; 0..5)
		//foreach(x; 0..SIZE)
		{
			auto i = z * SIZE + y * SIZE_SQR;
			writefln("%s", dest[i..i+5]);
		}
		writeln;
	}
}

int main(string[] args)
{
	string inputDirectory;
	string outputFile;
	ushort dimension;
	bool appendDimention;

	getopt(args, config.passThrough, config.required,
		"i|input", &inputDirectory,
		"o|output", &outputFile,
		"a", &appendDimention,
		"d|dimension", &dimension);

	inputDirectory = inputDirectory.absolutePath;

	if (!inputDirectory.exists) {
		writefln(`input directory "%s" does not exist`, inputDirectory);
		return 1;
	}

	if (!inputDirectory.isDir) {
		writefln(`input "%s" is not a directory`, inputDirectory);
		return 1;
	}

	if (outputFile.length == 0) {
		outputFile = inputDirectory.setExtension(worldExtension);
	}

	writefln(`input "%s"`, inputDirectory);
	writefln(`output "%s"`, outputFile);

	string regionDir = buildPath(inputDirectory, "region");

	if (!regionDir.exists) {
		writefln(`region directory "%s" does not exist`, regionDir);
		return 1;
	}

	transferRegions(regionDir, outputFile, dimension);

	return 0;
}

void transferRegions(string regionDir, string outputWorld, DimensionId dimensionId)
{
	WorldDb worldDb = new WorldDb;
	worldDb.open(outputWorld); // closed by storage thread

	BlockInfoTable blocks;

	ChunkProvider chunkProvider;
	chunkProvider.init(worldDb, 0, blocks);

	auto chunkManager = new ChunkManager;

	ubyte numLayers = 2;
	chunkManager.setup(numLayers);
	chunkManager.isChunkSavingEnabled = true;
	chunkManager.startChunkSave = &chunkProvider.startChunkSave;
	chunkManager.pushLayer = &chunkProvider.pushLayer;
	chunkManager.endChunkSave = &chunkProvider.endChunkSave;

	chunkManager.loadChunkHandler = (ChunkWorldPos){};
	chunkManager.isLoadCancelingEnabled = true;

	chunkProvider.onChunkLoadedHandler = &chunkManager.onSnapshotLoaded!LoadedChunkData;
	chunkProvider.onChunkSavedHandler = &chunkManager.onSnapshotSaved!SavedChunkData;

	auto observerManager = new ChunkObserverManager;
	observerManager.changeChunkNumObservers = &chunkManager.setExternalChunkObservers;
	observerManager.chunkObserverAdded = (ChunkWorldPos, ClientId){};

	McRegion region;
	region.buffer = new ubyte[1024 * 1024 * 10];
	size_t numRegions;
	size_t numChunkColumns;
	foreach(regionName; regionIterator(regionDir))
	{
		region.parseRegionFilename(regionName);
		writefln("region %s %s", region.x, region.z);

		foreach(chunkInfo; region)
		{
			//writefln("chunk %s %s", chunkInfo.x, chunkInfo.z);
			importChunk(region, chunkInfo, chunkManager, dimensionId);
			++numChunkColumns;
		}
		++numRegions;
	}

	chunkManager.commitSnapshots(TimestampType(0));

	chunkProvider.stop(); // updates until everything is saved
}

void importChunk(ref McRegion region, McChunkInfo chunkInfo, ChunkManager chunkManager, DimensionId dimensionId)
{
	ubyte[] data = chunkInfo.data;
	//std.file.write("test.data", data);
	//assert(false);

	ubyte[] blocks;
	long y;

	size_t y_counter;
	size_t blocks_counter;

	void trySection()
	{
		if (y_counter == blocks_counter)
		{
			auto cwp = ivec3(region.x * MC_REGION_WIDTH + chunkInfo.x, y, region.z * MC_REGION_WIDTH + chunkInfo.z);
			importSection(blocks, cwp, chunkManager, dimensionId);
		}
	}

	VisitRes sectionVisitor(ref ubyte[] input, NbtTag tag) {
		switch(tag.name)
		{
			case "Blocks":
				blocks = readBytes(input, tag.length);
				++blocks_counter;
				trySection();
				return VisitRes.r_continue;
			case "Y":
				y = tag.integer;
				++y_counter;
				trySection();
				return VisitRes.r_continue;
			default:
				return visitNbtValue(input, tag, &sectionVisitor);
		}
	}

	VisitRes visitor(ref ubyte[] input, NbtTag tag) {
		if (tag.name == "Sections") return visitNbtValue(input, tag, &sectionVisitor);
		else return visitNbtValue(input, tag, &visitor);
	}

	//printNbtStream(data);
	visitNbtStream(data, &visitor);
}

void fixNegativeOffset(ref int off)
{
	off = off < 0 ? off + MC_CHUNK_WIDTH : off;
}

void importSection(ubyte[] blocks, ivec3 mc_cwp, ChunkManager chunkManager, DimensionId dimensionId)
{
	ivec3 pos = ivec3(
		floor(cast(float)mc_cwp.x / 2),
		floor(cast(float)mc_cwp.y / 2),
		floor(cast(float)mc_cwp.z / 2));

	ivec3 offset = mc_cwp % 2;
	offset = ivec3(
		offset.x < 0 ? offset.x + 2 : offset.x,
		offset.y < 0 ? offset.y + 2 : offset.y,
		offset.z < 0 ? offset.z + 2 : offset.z) * MC_CHUNK_WIDTH;

	ivec3 size = ivec3(MC_CHUNK_WIDTH, MC_CHUNK_WIDTH, MC_CHUNK_WIDTH);

	// box within voxelman chunk.
	Box mcChunkBox = Box(offset, size);

	auto cwp = ChunkWorldPos(pos, dimensionId);

	WriteBuffer* wb = chunkManager.getOrCreateWriteBuffer(cwp, FIRST_LAYER, WriteBufferPolicy.createUniform, true);
	if (wb.isUniform)
	{
		wb.layer.dataLength = BLOCKID_UNIFORM_FILL_BITS;
		wb.layer.uniformData = AIR;
		expandUniformLayer(wb.layer);
	}

	BlockId[MC_CHUNK_WIDTH_CUBE] convertedBlocks;

	foreach(i, ubyte mcBlock; blocks)
	{
		convertedBlocks[i] = mcBlockToBlockId(mcBlock);
	}

	// set blocks
	setSubArray(wb.layer.getArray!BlockId, mcChunkBox, convertedBlocks);
}

BlockId mcBlockToBlockId(ubyte mcBlock)
{
	if (mcBlock == 0)
		return AIR;
	else
		return STONE;
}
