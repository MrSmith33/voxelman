/+ dub.sdl:
name "minecraft_import"
license "BSL-1.0"
authors "Andrey Penechko"
dependency "voxelman" path="../../"
mainSourceFile "main.d"
targetType "executable"
+/

import std.algorithm;
import std.file;
import std.getopt;
import std.path;
import std.stdio;

import voxelman.math;
import voxelman.core.config;
import voxelman.block.utils : BlockInfoTable;
import voxelman.world.storage.chunkmanager : ChunkManager;
import voxelman.world.storage.chunkprovider : ChunkProvider;
import voxelman.world.storage.chunkobservermanager : ChunkObserverManager;
import voxelman.world.worlddb : WorldDb;
import voxelman.geometry.box;
import voxelman.world.storage.worldbox;

enum worldExtension = ".db";
enum regionExt = ".mca";

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

	auto observerManager = new ChunkObserverManager;
	observerManager.changeChunkNumObservers = &chunkManager.setExternalChunkObservers;
	observerManager.chunkObserverAdded = (ChunkWorldPos, ClientId){};

	foreach(region; regionIterator(regionDir))
	{
		readRegion(region, chunkManager, dimensionId);
	}

	chunkProvider.stop();
}

void readRegion(McRegion region, ChunkManager chunkManager, DimensionId dimensionId)
{
	WorldBox regionBox = WorldBox(calcRegionBox(region), dimensionId);
	writefln(`region: "%s" %s, %s %s`, region.path, region.x, region.z, regionBox);
}

struct McRegion
{
	string path;
	int x, z;
}

enum MC_REGION_SIZE = 32;
enum MC_CHUNK_WIDTH = 16;
enum MC_CHUNK_HEIGHT = 256;
enum CHUNKS_PER_MC_REGION_WIDTH = MC_CHUNK_WIDTH * MC_REGION_SIZE / CHUNK_SIZE;
enum CHUNKS_PER_MC_REGION_HEIGHT = MC_CHUNK_HEIGHT / CHUNK_SIZE;

Box calcRegionBox(McRegion region)
{
	int x = region.x * CHUNKS_PER_MC_REGION_WIDTH;
	int y = 0;
	int z = region.z * CHUNKS_PER_MC_REGION_WIDTH;
	int sx = CHUNKS_PER_MC_REGION_WIDTH;
	int sy = CHUNKS_PER_MC_REGION_HEIGHT;
	int sz = CHUNKS_PER_MC_REGION_WIDTH;
	return Box(ivec3(x, y, z), ivec3(sx, sy, sz));
}

auto regionIterator(string regionDir)
{
	return dirEntries(regionDir, SpanMode.shallow)
		.filter!(entry => entry.isFile && extension(entry.name) == regionExt)
		.map!(entry => parseRegionInfo(entry));
}

McRegion parseRegionInfo(string regionFile)
{
	import std.regex : matchFirst, ctRegex;
	import std.conv : to;
	enum regionPattern = `r\.([-]?[0-9]+)\.([-]?[0-9]+)`;

	string name = regionFile.baseName.stripExtension;
	auto c = matchFirst(name, ctRegex!(regionPattern, "m"));
	int x = to!int(c[1]);
	int z = to!int(c[2]);
	return McRegion(regionFile, x, z);
}
