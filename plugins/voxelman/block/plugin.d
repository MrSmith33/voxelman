/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.block.plugin;

import std.experimental.logger;
import std.array : array;
import cbor;
import pluginlib;
import voxelman.core.config : BlockId;
import voxelman.world.storage.coordinates;
import voxelman.block.utils;
import voxelman.utils.mapping;

import voxelman.world.plugin;
import voxelman.world.clientworld;

final class BlockManager : IResourceManager
{
private:
	Mapping!BlockInfo blockMapping;

public:
	override string id() @property { return "voxelman.block.blockmanager"; }
	override void preInit()
	{
		regBaseBlocks(&regBlock);
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
	immutable string blockMappingKey = "voxelman.block.block_mapping";

	override void registerResourceManagers(void delegate(IResourceManager) registerHandler)
	{
		registerHandler(bm = new BlockManager);
	}

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		registerResourcesImpl(resmanRegistry);
	}

	BlockInfoTable getBlocks()
	{
		return BlockInfoTable(cast(immutable)bm.blockMapping.infoArray);
	}
}

final class BlockPluginClient : IPlugin
{
	mixin BlockPluginCommonImpl;
	// IPlugin stuff
	mixin IdAndSemverFrom!(voxelman.block.plugininfo);

	override void init(IPluginManager pluginman)
	{
		auto clientWorld = pluginman.getPlugin!ClientWorld;
		clientWorld.idMapManager.regIdMapHandler(blockMappingKey, &handleBlockMap);
	}

	void handleBlockMap(string[] blocks)
	{
		bm.blockMapping.setMapping(blocks);
	}

	void registerResourcesImpl(IResourceManagerRegistry resmanRegistry){}
}

final class BlockPluginServer : IPlugin
{
	mixin BlockPluginCommonImpl;
	// IPlugin stuff
	mixin IdAndSemverFrom!(voxelman.block.plugininfo);

	void registerResourcesImpl(IResourceManagerRegistry resmanRegistry)
	{
		auto ioman = resmanRegistry.getResourceManager!IoManager;
		ioman.registerWorldLoadSaveHandlers(&readBlockMap, &writeBlockMap);
	}

	override void init(IPluginManager pluginman)
	{
		auto serverWorld = pluginman.getPlugin!ServerWorld;
		serverWorld.idMapManager.regIdMap(blockMappingKey, bm.blockMapping.nameRange.array);
	}

	void readBlockMap(ref PluginDataLoader loader)
	{
		ubyte[] data = loader.readEntry(blockMappingKey);

		if (data.length)
		{
			string[] blocks = decodeCborSingleDup!(string[])(data);
			bm.blockMapping.setMapping(blocks);
		}
	}

	void writeBlockMap(ref PluginDataSaver saver)
	{
		auto sink = saver.tempBuffer;
		size_t size = 0;
		auto blockInfos = bm.blockMapping.infoArray;
		size = encodeCborArrayHeader(sink[], blockInfos.length);
		foreach(info; blockInfos)
			size += encodeCbor(sink[size..$], info.name);
		saver.writeEntry(blockMappingKey, size);
	}
}
