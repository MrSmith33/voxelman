/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module main;

import std.algorithm;
import std.file;
import std.getopt;
import std.path;
import std.stdio;
import std.string : format;

import voxelman.log;
import voxelman.math;
import voxelman.geometry.rect;
import voxelman.utils.mapping;

import pluginlib;
import pluginlib.pluginmanager;

import voxelman.core.events;
import voxelman.core.config;
import voxelman.world.block;
import voxelman.world.storage;
import voxelman.world.worlddb : WorldDb;
import voxelman.world.gen.utils;

import voxelman.block.plugin;
import voxelman.blockentity.plugin;
import voxelman.client.plugin;
import voxelman.command.plugin;
import voxelman.config.plugin;
import voxelman.dbg.plugin;
import voxelman.entity.plugin;
import voxelman.eventdispatcher.plugin;
import voxelman.net.plugin;
import voxelman.server.plugin;
import voxelman.session.server;
import voxelman.world.serverworld;

import mc_region;
import nbt;

enum worldExtension = ".db";

struct ImportParams
{
	string inputDirectory;
	string outputFile;
	string outputDirectory;
	string outputWorldName;
	DimensionId outDimension;
	bool appendDimention;
	string regionDir;
	bool centerRegions;
	ivec3 importedSpawn; // spawn pos after map centering. In blocks.
	ivec2 heading; // camera rotation in degrees
}

int main(string[] args)
{
	ImportParams params;
	int[] spawnPos;
	int[] heading;

	auto tempSep = std.getopt.arraySep;
	std.getopt.arraySep = ",";
	getopt(args, config.passThrough, config.required,
		"i|input", &params.inputDirectory,
		"o|output", &params.outputFile,
		//"a", &params.appendDimention,
		"center", &params.centerRegions,
		"d|dimension", &params.outDimension,
		//"spawn", &spawnPos,
		//"heading", &heading,
		);
	std.getopt.arraySep = tempSep;

	writefln("Spawn pos %s", spawnPos);
	writefln("Camera heading %s", heading);

	params.inputDirectory = params.inputDirectory.absolutePath;

	if (!params.inputDirectory.exists) {
		writefln(`Input directory "%s" does not exist`, params.inputDirectory);
		return 1;
	}

	if (!params.inputDirectory.isDir) {
		writefln(`Input "%s" is not a directory`, params.inputDirectory);
		return 1;
	}

	if (params.outputFile.length == 0) {
		params.outputFile = params.inputDirectory.setExtension(worldExtension);
	}

	writefln(`Input "%s"`, params.inputDirectory);
	writefln(`Output "%s"`, params.outputFile);

	params.outputWorldName = params.outputFile.baseName.stripExtension;
	params.outputDirectory = params.outputFile.dirName.relativePath;
	writefln(`--save_dir="%s" --world_name="%s"`, params.outputDirectory, params.outputWorldName);

	params.regionDir = buildPath(params.inputDirectory, "region");

	if (!params.regionDir.exists) {
		writefln(`Region directory "%s" does not exist`, params.regionDir);
		return 1;
	}

	string[] newArgs = args;
	newArgs ~= format(`--world_name=%s`, params.outputWorldName);
	newArgs ~= format(`--save_dir=%s`, params.outputDirectory);

	serverMain1(params, newArgs);

	return 0;
}

void serverMain1(ImportParams params, string[] args)
{
	import enginestarter;

	EngineStarter engineStarter;
	engineStarter.setupLogs(EngineStarter.AppType.server);
	scope(exit) closeBinLog();

	auto pluginman = new PluginManager;

	pluginman.registerPlugin(new BlockPluginServer);
	pluginman.registerPlugin(new BlockEntityServer);
	pluginman.registerPlugin(new CommandPluginServer);
	pluginman.registerPlugin(new ConfigPlugin(CONFIG_FILE_NAME_SERVER, args));
	pluginman.registerPlugin(new DebugServer);
	pluginman.registerPlugin(new EntityPluginServer);
	pluginman.registerPlugin(new EventDispatcherPlugin);
	pluginman.registerPlugin(new NetServerPlugin);
	pluginman.registerPlugin(new ClientManager);
	pluginman.registerPlugin(new ServerWorld);

	pluginman.initPlugins();

	serverMain2(pluginman, params);

	engineStarter.waitForThreads();
}

void serverMain2(PluginManager pluginman, ImportParams params)
{
	EventDispatcherPlugin evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
	auto bm = pluginman.getResourceManager!BlockManager;
	BlockInfoTable blocks = bm.getBlocks();
	auto serverWorld = pluginman.getPlugin!ServerWorld;

	evDispatcher.postEvent(GameStartEvent());

	transferRegions(params, serverWorld, blocks);

	infof("Saving...");
	evDispatcher.postEvent(WorldSaveInternalEvent());
	infof("Stopping...");
	evDispatcher.postEvent(GameStopEvent());
}

void transferRegions(ImportParams params, ServerWorld serverWorld, BlockInfoTable blocks)
{
	setDimensionBorders(serverWorld, params.outDimension);
	transferRegionsImpl(params, serverWorld.chunkEditor, serverWorld.chunkProvider, blocks);

	updateMetadata(serverWorld.chunkEditor.getWriteBuffers(BLOCK_LAYER), blocks);
	serverWorld.chunkEditor.commitSnapshots(TimestampType(0));
}

void setDimensionBorders(ServerWorld serverWorld, DimensionId outDimension)
{
	DimensionInfo* dimInfo = serverWorld.dimMan.getOrCreate(outDimension);
	dimInfo.borders.position.y = 0;
	dimInfo.borders.size.y = 8;
}

void transferRegionsImpl(ImportParams params, ChunkEditor chunkEditor,
	ChunkProvider chunkProvider, BlockInfoTable blocks)
{
	McRegion region;
	region.buffer = new ubyte[1024 * 1024 * 10];
	size_t numRegions;
	size_t numChunkColumns;

	// Rectangle that contains all region positions. Used to center imported map.
	Rect regionRect;

	foreach(regionName; regionIterator(params.regionDir))
	{
		region.parseRegionFilename(regionName);
		++numRegions;

		if (numRegions == 1)
			regionRect = Rect(ivec2(region.x, region.z));
		else
			regionRect.add(ivec2(region.x, region.z));
	}
	writefln("found %s regions: area from %s to %s", numRegions,
		regionRect.position, regionRect.endPosition);

	// offset added to position of imported regions
	ivec2 regionOffset;
	if (params.centerRegions)
	{
		regionOffset = -(regionRect.position + regionRect.size/2);
	}
	writefln("Offseting imported regions by %s", regionOffset);

	size_t currentRegionIndex;
	foreach(regionName; regionIterator(params.regionDir))
	{
		region.parseRegionFilename(regionName);

		writef("%s/%s\tregion %s %s -> ", currentRegionIndex, numRegions, region.x, region.z);

		region.x += regionOffset.x;
		region.z += regionOffset.y;

		writefln("%s %s", region.x, region.z);

		foreach(chunkInfo; region)
		{
			//writefln("chunk %s %s", chunkInfo.x, chunkInfo.z);
			importChunk(region, chunkInfo, chunkEditor, params.outDimension);
			++numChunkColumns;
		}

		updateMetadata(chunkEditor.getWriteBuffers(BLOCK_LAYER), blocks);
		chunkEditor.commitSnapshots(TimestampType(0));
		++currentRegionIndex;
		chunkProvider.update();
	}
}

void updateMetadata(WriteBuffer[ChunkWorldPos] writeBuffers, BlockInfoTable blockInfos)
{
	foreach(ref writeBuffer; writeBuffers.byValue)
	{
		writeBuffer.layer.metadata = calcChunkFullMetadata(writeBuffer.layer, blockInfos);
	}
}

void importChunk(ref McRegion region, McChunkInfo chunkInfo, ChunkEditor chunkEditor, DimensionId outDimension)
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
			importSection(blocks, cwp, chunkEditor, outDimension);
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

void importSection(ubyte[] blocks, ivec3 mc_cwp, ChunkEditor chunkEditor, DimensionId outDimension)
{
	//writefln("section %s", mc_cwp);
	ivec3 pos = ivec3(
		floor(cast(float)mc_cwp.x / 2),
		floor(cast(float)mc_cwp.y / 2),
		floor(cast(float)mc_cwp.z / 2));

	ivec3 destPos = mc_cwp % 2;
	destPos = ivec3(
		destPos.x < 0 ? destPos.x + 2 : destPos.x,
		destPos.y < 0 ? destPos.y + 2 : destPos.y,
		destPos.z < 0 ? destPos.z + 2 : destPos.z) * MC_CHUNK_WIDTH;

	const ivec3 mcChunkSize = ivec3(MC_CHUNK_WIDTH, MC_CHUNK_WIDTH, MC_CHUNK_WIDTH);

	// box within voxelman chunk.
	Box sourceBox =  Box(ivec3(0,0,0), mcChunkSize);

	auto cwp = ChunkWorldPos(pos, outDimension);

	WriteBuffer* wb = chunkEditor.getOrCreateWriteBuffer(cwp, BLOCK_LAYER, WriteBufferPolicy.createUniform, true);
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
	setSubArray3d(wb.layer.getArray!BlockId, CHUNK_SIZE_VECTOR, destPos, convertedBlocks, mcChunkSize, sourceBox);
}

enum WOOD = DIRT;
enum LEAVES = GRASS;
enum GLASS = WATER;
BlockId mcBlockToBlockId(ubyte mcBlock)
{
	switch(mcBlock)
	{
		case 0: return AIR; //Air
		case 1: return STONE; //Stone
		//case 1:1: return ; //Granite
		//case 1:2: return ; //Polished Granite
		//case 1:3: return ; //Diorite
		//case 1:4: return ; //Polished Diorite
		//case 1:5: return ; //Andesite
		//case 1:6: return ; //Polished Andesite
		case 2: return GRASS; //Grass
		case 3: return DIRT; //Dirt
		//case 3:1: return ; //Coarse Dirt
		//case 3:2: return ; //Podzol
		case 4: return STONE; //Cobblestone
		case 5: return WOOD; //Oak Wood Plank
		//case 5:1: return ; //Spruce Wood Plank
		//case 5:2: return ; //Birch Wood Plank
		//case 5:3: return ; //Jungle Wood Plank
		//case 5:4: return ; //Acacia Wood Plank
		//case 5:5: return ; //Dark Oak Wood Plank
		case 6: return GRASS; //Oak Sapling
		//case 6:1: return ; //Spruce Sapling
		//case 6:2: return ; //Birch Sapling
		//case 6:3: return ; //Jungle Sapling
		//case 6:4: return ; //Acacia Sapling
		//case 6:5: return ; //Dark Oak Sapling
		case 7: return STONE; //Bedrock
		case 8: return WATER; //Flowing Water
		case 9: return WATER; //Still Water
		case 10: return LAVA; //Flowing Lava
		case 11: return LAVA; //Still Lava
		case 12: return SAND; //Sand
		//case 12:1: return SAND; //Red Sand
		case 13: return STONE; //Gravel
		case 14: return STONE; //Gold Ore
		case 15: return STONE; //Iron Ore
		case 16: return STONE; //Coal Ore
		case 17: return WOOD; //Oak Wood
		//case 17:1: return ; //Spruce Wood
		//case 17:2: return ; //Birch Wood
		//case 17:3: return ; //Jungle Wood
		case 18: return LEAVES; //Oak Leaves
		//case 18:1: return ; //Spruce Leaves
		//case 18:2: return ; //Birch Leaves
		//case 18:3: return ; //Jungle Leaves
		case 19: return SAND; //Sponge
		//case 19:1: return ; //Wet Sponge
		case 20: return GLASS; //Glass
		case 21: return STONE; //Lapis Lazuli Ore
		case 22: return STONE; //Lapis Lazuli Block
		case 23: return STONE; //Dispenser
		case 24: return SAND; //Sandstone
		//case 24:1: return ; //Chiseled Sandstone
		//case 24:2: return ; //Smooth Sandstone
		case 25: return WOOD; //Note Block
		case 26: return WOOD; //Bed
		case 27: return STONE; //Powered Rail
		case 28: return STONE; //Detector Rail
		case 29: return WOOD; //Sticky Piston
		case 30: return SNOW; //Cobweb
		case 31: return WOOD; //Dead Shrub
		//case 31:1: return GRASS; //Grass
		//case 31:2: return WOOD; //Fern
		case 32: return WOOD; //Dead Bush
		case 33: return STONE; //Piston
		case 34: return WOOD; //Piston Head
		case 35: return SNOW; //White Wool
		//case 35:1: return ; //Orange Wool
		//case 35:2: return ; //Magenta Wool
		//case 35:3: return ; //Light Blue Wool
		//case 35:4: return ; //Yellow Wool
		//case 35:5: return ; //Lime Wool
		//case 35:6: return ; //Pink Wool
		//case 35:7: return ; //Gray Wool
		//case 35:8: return ; //Light Gray Wool
		//case 35:9: return ; //Cyan Wool
		//case 35:10: return ; //Purple Wool
		//case 35:11: return ; //Blue Wool
		//case 35:12: return ; //Brown Wool
		//case 35:13: return ; //Green Wool
		//case 35:14: return ; //Red Wool
		//case 35:15: return ; //Black Wool
		case 37: return GRASS; //Dandelion
		case 38: return GRASS; //Poppy
		//case 38:1: return ; //Blue Orchid
		//case 38:2: return ; //Allium
		//case 38:3: return ; //Azure Bluet
		//case 38:4: return ; //Red Tulip
		//case 38:5: return ; //Orange Tulip
		//case 38:6: return ; //White Tulip
		//case 38:7: return ; //Pink Tulip
		//case 38:8: return ; //Oxeye Daisy
		case 39: return WOOD; //Brown Mushroom
		case 40: return WOOD; //Red Mushroom
		case 41: return SAND; //Gold Block
		case 42: return SNOW; //Iron Block
		case 43: return STONE; //Double Stone Slab
		//case 43:1: return ; //Double Sandstone Slab
		//case 43:2: return ; //Double Wooden Slab
		//case 43:3: return ; //Double Cobblestone Slab
		//case 43:4: return ; //Double Brick Slab
		//case 43:5: return ; //Double Stone Brick Slab
		//case 43:6: return ; //Double Nether Brick Slab
		//case 43:7: return ; //Double Quartz Slab
		case 44: return STONE; //Stone Slab
		//case 44:1: return ; //Sandstone Slab
		//case 44:2: return ; //Wooden Slab
		//case 44:3: return ; //Cobblestone Slab
		//case 44:4: return ; //Brick Slab
		//case 44:5: return ; //Stone Brick Slab
		//case 44:6: return ; //Nether Brick Slab
		//case 44:7: return ; //Quartz Slab
		case 45: return DIRT; //Bricks
		case 46: return DIRT; //TNT
		case 47: return WOOD; //Bookshelf
		case 48: return STONE; //Moss Stone
		case 49: return STONE; //Obsidian
		case 50: return LAVA; //Torch
		case 51: return LAVA; //Fire
		case 52: return STONE; //Monster Spawner
		case 53: return WOOD; //Oak Wood Stairs
		case 54: return WOOD; //Chest
		case 55: return WOOD; //Redstone Wire
		case 56: return STONE; //Diamond Ore
		case 57: return SNOW; //Diamond Block
		case 58: return WOOD; //Crafting Table
		case 59: return GRASS; //Wheat Crops
		case 60: return DIRT; //Farmland
		case 61: return STONE; //Furnace
		case 62: return STONE; //Burning Furnace
		case 63: return WOOD; //Standing Sign Block
		case 64: return WOOD; //Oak Door Block
		case 65: return WOOD; //Ladder
		case 66: return STONE; //Rail
		case 67: return STONE; //Cobblestone Stairs
		case 68: return WOOD; //Wall-mounted Sign Block
		case 69: return WOOD; //Lever
		case 70: return STONE; //Stone Pressure Plate
		case 71: return STONE; //Iron Door Block
		case 72: return WOOD; //Wooden Pressure Plate
		case 73: return STONE; //Redstone Ore
		case 74: return LAVA; //Glowing Redstone Ore
		case 75: return LAVA; //Redstone Torch (off)
		case 76: return LAVA; //Redstone Torch (on)
		case 77: return STONE; //Stone Button
		case 78: return SNOW; //Snow
		case 79: return SNOW; //Ice
		case 80: return SNOW; //Snow Block
		case 81: return GRASS; //Cactus
		case 82: return SAND; //Clay
		case 83: return GRASS; //Sugar Canes
		case 84: return WOOD; //Jukebox
		case 85: return WOOD; //Oak Fence
		case 86: return SAND; //Pumpkin
		case 87: return SAND; //Netherrack
		case 88: return SAND; //Soul Sand
		case 89: return LAVA; //Glowstone
		case 90: return WATER; //Nether Portal
		case 91: return LAVA; //Jack o'Lantern
		case 92: return SAND; //Cake Block
		case 93: return STONE; //Redstone Repeater Block (off)
		case 94: return STONE; //Redstone Repeater Block (on)
		case 95: return STONE; //White Stained Glass
		//case 95:1: return ; //Orange Stained Glass
		//case 95:2: return ; //Magenta Stained Glass
		//case 95:3: return ; //Light Blue Stained Glass
		//case 95:4: return ; //Yellow Stained Glass
		//case 95:5: return ; //Lime Stained Glass
		//case 95:6: return ; //Pink Stained Glass
		//case 95:7: return ; //Gray Stained Glass
		//case 95:8: return ; //Light Gray Stained Glass
		//case 95:9: return ; //Cyan Stained Glass
		//case 95:10: return ; //Purple Stained Glass
		//case 95:11: return ; //Blue Stained Glass
		//case 95:12: return ; //Brown Stained Glass
		//case 95:13: return ; //Green Stained Glass
		//case 95:14: return ; //Red Stained Glass
		//case 95:15: return ; //Black Stained Glass
		case 96: return WOOD; //Wooden Trapdoor
		case 97: return STONE; //Stone Monster Egg
		//case 97:1: return ; //Cobblestone Monster Egg
		//case 97:2: return ; //Stone Brick Monster Egg
		//case 97:3: return ; //Mossy Stone Brick Monster Egg
		//case 97:4: return ; //Cracked Stone Brick Monster Egg
		//case 97:5: return ; //Chiseled Stone Brick Monster Egg
		case 98: return STONE; //Stone Bricks
		//case 98:1: return ; //Mossy Stone Bricks
		//case 98:2: return ; //Cracked Stone Bricks
		//case 98:3: return ; //Chiseled Stone Bricks
		case 99: return WOOD; //Brown Mushroom Block
		case 100: return WOOD; //Red Mushroom Block
		case 101: return STONE; //Iron Bars
		case 102: return GRASS; //Glass Pane
		case 103: return GRASS; //Melon Block
		case 104: return GRASS; //Pumpkin Stem
		case 105: return GRASS; //Melon Stem
		case 106: return GRASS; //Vines
		case 107: return WOOD; //Oak Fence Gate
		case 108: return STONE; //Brick Stairs
		case 109: return STONE; //Stone Brick Stairs
		case 110: return SAND; //Mycelium
		case 111: return GRASS; //Lily Pad
		case 112: return STONE; //Nether Brick
		case 113: return STONE; //Nether Brick Fence
		case 114: return STONE; //Nether Brick Stairs
		case 115: return STONE; //Nether Wart
		case 116: return STONE; //Enchantment Table
		case 117: return STONE; //Brewing Stand
		case 118: return STONE; //Cauldron
		case 119: return SAND; //End Portal
		case 120: return SAND; //End Portal Frame
		case 121: return SAND; //End Stone
		case 122: return SAND; //Dragon Egg
		case 123: return LAVA; //Redstone Lamp (inactive)
		case 124: return LAVA; //Redstone Lamp (active)
		case 125: return WOOD; //Double Oak Wood Slab
		//case 125:1: return ; //Double Spruce Wood Slab
		//case 125:2: return ; //Double Birch Wood Slab
		//case 125:3: return ; //Double Jungle Wood Slab
		//case 125:4: return ; //Double Acacia Wood Slab
		//case 125:5: return ; //Double Dark Oak Wood Slab
		case 126: return WOOD; //Oak Wood Slab
		//case 126:1: return ; //Spruce Wood Slab
		//case 126:2: return ; //Birch Wood Slab
		//case 126:3: return ; //Jungle Wood Slab
		//case 126:4: return ; //Acacia Wood Slab
		//case 126:5: return ; //Dark Oak Wood Slab
		case 127: return WOOD; //Cocoa
		case 128: return SAND; //Sandstone Stairs
		case 129: return STONE; //Emerald Ore
		case 130: return WOOD; //Ender Chest
		case 131: return STONE; //Tripwire Hook
		case 132: return STONE; //Tripwire
		case 133: return GRASS; //Emerald Block
		case 134: return WOOD; //Spruce Wood Stairs
		case 135: return WOOD; //Birch Wood Stairs
		case 136: return WOOD; //Jungle Wood Stairs
		case 137: return WOOD; //Command Block
		case 138: return STONE; //Beacon
		case 139: return STONE; //Cobblestone Wall
		//case 139:1: return ; //Mossy Cobblestone Wall
		case 140: return WOOD; //Flower Pot
		case 141: return WOOD; //Carrots
		case 142: return WOOD; //Potatoes
		case 143: return WOOD; //Wooden Button
		case 144: return GRASS; //Mob Head
		case 145: return STONE; //Anvil
		case 146: return WOOD; //Trapped Chest
		case 147: return STONE; //Weighted Pressure Plate (light)
		case 148: return STONE; //Weighted Pressure Plate (heavy)
		case 149: return STONE; //Redstone Comparator (inactive)
		case 150: return STONE; //Redstone Comparator (active)
		case 151: return STONE; //Daylight Sensor
		case 152: return STONE; //Redstone Block
		case 153: return STONE; //Nether Quartz Ore
		case 154: return STONE; //Hopper
		case 155: return SNOW; //Quartz Block
		//case 155:1: return ; //Chiseled Quartz Block
		//case 155:2: return ; //Pillar Quartz Block
		case 156: return SNOW; //Quartz Stairs
		case 157: return STONE; //Activator Rail
		case 158: return WOOD; //Dropper
		case 159: return SAND; //White Stained Clay
		//case 159:1: return ; //Orange Stained Clay
		//case 159:2: return ; //Magenta Stained Clay
		//case 159:3: return ; //Light Blue Stained Clay
		//case 159:4: return ; //Yellow Stained Clay
		//case 159:5: return ; //Lime Stained Clay
		//case 159:6: return ; //Pink Stained Clay
		//case 159:7: return ; //Gray Stained Clay
		//case 159:8: return ; //Light Gray Stained Clay
		//case 159:9: return ; //Cyan Stained Clay
		//case 159:10: return ; //Purple Stained Clay
		//case 159:11: return ; //Blue Stained Clay
		//case 159:12: return ; //Brown Stained Clay
		//case 159:13: return ; //Green Stained Clay
		//case 159:14: return ; //Red Stained Clay
		//case 159:15: return ; //Black Stained Clay
		case 160: return GLASS; //White Stained Glass Pane
		//case 160:1: return ; //Orange Stained Glass Pane
		//case 160:2: return ; //Magenta Stained Glass Pane
		//case 160:3: return ; //Light Blue Stained Glass Pane
		//case 160:4: return ; //Yellow Stained Glass Pane
		//case 160:5: return ; //Lime Stained Glass Pane
		//case 160:6: return ; //Pink Stained Glass Pane
		//case 160:7: return ; //Gray Stained Glass Pane
		//case 160:8: return ; //Light Gray Stained Glass Pane
		//case 160:9: return ; //Cyan Stained Glass Pane
		//case 160:10: return ; //Purple Stained Glass Pane
		//case 160:11: return ; //Blue Stained Glass Pane
		//case 160:12: return ; //Brown Stained Glass Pane
		//case 160:13: return ; //Green Stained Glass Pane
		//case 160:14: return ; //Red Stained Glass Pane
		//case 160:15: return ; //Black Stained Glass Pane
		case 161: return LEAVES; //Acacia Leaves
		//case 161:1: return ; //Dark Oak Leaves
		case 162: return WOOD; //Acacia Wood
		//case 162:1: return ; //Dark Oak Wood
		case 163: return WOOD; //Acacia Wood Stairs
		case 164: return WOOD; //Dark Oak Wood Stairs
		case 165: return GRASS; //Slime Block
		case 166: return WOOD; //Barrier
		case 167: return WOOD; //Iron Trapdoor
		case 168: return WOOD; //Prismarine
		//case 168:1: return ; //Prismarine Bricks
		//case 168:2: return ; //Dark Prismarine
		case 169: return WOOD; //Sea Lantern
		case 170: return WOOD; //Hay Bale
		case 171: return WOOD; //White Carpet
		//case 171:1: return ; //Orange Carpet
		//case 171:2: return ; //Magenta Carpet
		//case 171:3: return ; //Light Blue Carpet
		//case 171:4: return ; //Yellow Carpet
		//case 171:5: return ; //Lime Carpet
		//case 171:6: return ; //Pink Carpet
		//case 171:7: return ; //Gray Carpet
		//case 171:8: return ; //Light Gray Carpet
		//case 171:9: return ; //Cyan Carpet
		//case 171:10: return ; //Purple Carpet
		//case 171:11: return ; //Blue Carpet
		//case 171:12: return ; //Brown Carpet
		//case 171:13: return ; //Green Carpet
		//case 171:14: return ; //Red Carpet
		//case 171:15: return ; //Black Carpet
		case 172: return SAND; //Hardened Clay
		case 173: return STONE; //Block of Coal
		case 174: return WATER; //Packed Ice
		case 175: return GRASS; //Sunflower
		//case 175:1: return ; //Lilac
		//case 175:2: return ; //Double Tallgrass
		//case 175:3: return ; //Large Fern
		//case 175:4: return ; //Rose Bush
		//case 175:5: return ; //Peony
		case 176: return WOOD; //Free-standing Banner
		case 177: return WOOD; //Wall-mounted Banner
		case 178: return WOOD; //Inverted Daylight Sensor
		case 179: return SAND; //Red Sandstone
		//case 179:1: return ; //Chiseled Red Sandstone
		//case 179:2: return ; //Smooth Red Sandstone
		case 180: return SAND; //Red Sandstone Stairs
		case 181: return SAND; //Double Red Sandstone Slab
		case 182: return SAND; //Red Sandstone Slab
		case 183: return WOOD; //Spruce Fence Gate
		case 184: return WOOD; //Birch Fence Gate
		case 185: return WOOD; //Jungle Fence Gate
		case 186: return WOOD; //Dark Oak Fence Gate
		case 187: return WOOD; //Acacia Fence Gate
		case 188: return WOOD; //Spruce Fence
		case 189: return WOOD; //Birch Fence
		case 190: return WOOD; //Jungle Fence
		case 191: return WOOD; //Dark Oak Fence
		case 192: return WOOD; //Acacia Fence
		case 193: return WOOD; //Spruce Door Block
		case 194: return WOOD; //Birch Door Block
		case 195: return WOOD; //Jungle Door Block
		case 196: return WOOD; //Acacia Door Block
		case 197: return WOOD; //Dark Oak Door Block
		case 198: return STONE; //End Rod
		case 199: return STONE; //Chorus Plant
		case 200: return STONE; //Chorus Flower
		case 201: return STONE; //Purpur Block
		case 202: return STONE; //Purpur Pillar
		case 203: return STONE; //Purpur Stairs
		case 204: return STONE; //Purpur Double Slab
		case 205: return STONE; //Purpur Slab
		case 206: return SAND; //End Stone Bricks
		case 207: return SAND; //Beetroot Block
		case 208: return GRASS; //Grass Path
		case 209: return WOOD; //End Gateway
		case 210: return WOOD; //Repeating Command Block
		case 211: return WOOD; //Chain Command Block
		case 212: return WATER; //Frosted Ice
		case 255: return WOOD; //Structure Block
		default: return STONE;
	}
}
