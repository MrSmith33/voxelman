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

final class BlockManager : IResourceManager
{
private:
	Mapping!BlockInfo blockMapping;

public:
	override string id() @property { return "voxelman.block.blockmanager"; }
	override void preInit()
	{
		regBlock("unknown").color(0,0,0).isVisible(false).isSolid(true).meshHandler(&makeNullMesh);
		regBlock("air").color(0,0,0).isVisible(false).isSolid(false).meshHandler(&makeNullMesh);
	}

	BlockInfoSetter regBlock(string name) {
		size_t id = blockMapping.put(BlockInfo(name));
		assert(id <= BlockId.max);
		return BlockInfoSetter(&blockMapping, id);
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
		bm.regBlock("grass").colorHex(0x7EEE11).meshHandler(&makeColoredBlockMesh);
		bm.regBlock("dirt").colorHex(0x835929).meshHandler(&makeColoredBlockMesh);
		bm.regBlock("stone").colorHex(0x8B8D7A).meshHandler(&makeColoredBlockMesh);
		bm.regBlock("sand").colorHex(0xA68117).meshHandler(&makeColoredBlockMesh);
		bm.regBlock("water").colorHex(0x0055AA).meshHandler(&makeColoredBlockMesh);
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
		//infof("received block map %s", blocks);
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
		size = encodeCborArrayHeader(sink[], blockInfos.length);
		foreach(info; blockInfos)
			size += encodeCbor(sink[size..$], info.name);
		wdb.savePerWorldData(blockMappingKey, sink[0..size]);
	}
}
