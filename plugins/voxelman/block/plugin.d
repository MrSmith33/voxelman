/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.block.plugin;

import std.experimental.logger;
import std.array : Appender, array;
import cbor;
import pluginlib;
import voxelman.core.config : BlockId;
import voxelman.storage.coordinates;
import voxelman.block.utils;
import voxelman.utils.mapping;

import voxelman.net.plugin;
import voxelman.world.plugin;

shared static this()
{
	pluginRegistry.regClientPlugin(new BlockPluginClient);
	pluginRegistry.regServerPlugin(new BlockPluginServer);
}


alias BlockUpdateHandler = void delegate(BlockWorldPos bwp);
alias Meshhandler = void function(ref Appender!(ubyte[]) output,
	ubyte[3] color, ubyte bx, ubyte by, ubyte bz, ubyte sides);

struct BlockInfo
{
	string name;
	Meshhandler meshHandler;
	ubyte[3] color;
	bool isVisible;
	bool isTransparent;
	size_t id;
}

final class BlockManager : IResourceManager
{
private:
	Mapping!BlockInfo blockMapping;

public:
	override string id() @property { return "voxelman.block.blockmanager"; }
	override void preInit()
	{
		regBlock("unknown", [0,0,0], false, false, &makeNullMesh);
		regBlock("air", [0,0,0], false, true, &makeNullMesh);
	}

	BlockId regBlock(string name, ubyte[3] color, bool isVisible,
		bool isTransparent, Meshhandler meshHandler)
	{
		auto id = blockMapping.put(BlockInfo(name, meshHandler, color, isVisible, isTransparent));
		assert(id <= BlockId.max);
		return cast(BlockId)id;
	}
}

mixin template BlockPluginCommonImpl()
{
	private BlockManager bm;
	// IPlugin stuff
	mixin IdAndSemverFrom!(voxelman.block.plugininfo);
	immutable string blockMappingKey = "voxelman.block.block_mapping";

	override void registerResourceManagers(void delegate(IResourceManager) registerHandler)
	{
		registerHandler(bm = new BlockManager);
	}

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		bm.regBlock("grass", [0, 255, 0], true, false, &makeColoredBlockMesh);
		bm.regBlock("dirt", [120, 72, 0], true, false, &makeColoredBlockMesh);
		bm.regBlock("stone", [128, 128, 128], true, false, &makeColoredBlockMesh);
		bm.regBlock("sand", [225, 169, 95], true, false, &makeColoredBlockMesh);
		registerResourcesImpl(resmanRegistry);
	}

	immutable(BlockInfo)[] getBlocks()
	{
		return cast(typeof(return))bm.blockMapping.infoArray;
	}
}

final class BlockPluginClient : IPlugin
{
	mixin BlockPluginCommonImpl;

	override void init(IPluginManager pluginman)
	{
		auto connection = pluginman.getPlugin!NetClientPlugin;
		connection.regIdMapHandler(blockMappingKey, &handleBlockMap);
	}

	void handleBlockMap(string[] blocks)
	{
		bm.blockMapping.setMapping(blocks);
		infof("received block map");
	}

	void registerResourcesImpl(IResourceManagerRegistry resmanRegistry){}
}

final class BlockPluginServer : IPlugin
{
	mixin BlockPluginCommonImpl;

	void registerResourcesImpl(IResourceManagerRegistry resmanRegistry)
	{
		auto ioman = resmanRegistry.getResourceManager!IoManager;
		ioman.registerWorldLoadHandler(&handleWorldLoad);
	}

	override void init(IPluginManager pluginman)
	{
		auto connection = pluginman.getPlugin!NetServerPlugin;
		connection.regIdMap(blockMappingKey, bm.blockMapping.nameRange.array);
	}

	void handleWorldLoad(WorldDb wdb) // Main thread
	{
		ubyte[] data = wdb.loadPerWorldData(blockMappingKey);
		scope(exit) wdb.perWorldSelectStmt.reset();

		if (data !is null)
		{
			string[] blocks = decodeCborSingleDup!(string[])(data);
			bm.blockMapping.setMapping(blocks);
		}

		auto sink = wdb.tempBuffer;
		size_t size = 0;
		auto blockInfos = bm.blockMapping.infoArray;
		size = encodeCborArrayHead(sink[], blockInfos.length);
		foreach(info; blockInfos)
			size += encodeCbor(sink[size..$], info.name);
		wdb.savePerWorldData(blockMappingKey, sink[0..size]);
	}
}
