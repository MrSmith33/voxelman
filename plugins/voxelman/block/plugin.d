/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.block.plugin;

import voxelman.log;
import std.array : array;
import cbor;
import pluginlib;
import voxelman.core.config : BlockId;
import voxelman.world.storage;
import voxelman.block.utils;
import voxelman.utils.mapping;

import voxelman.world.serverworld;
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

	BlockInfoTable getBlocks() {
		return BlockInfoTable(cast(immutable)blockMapping.infoArray);
	}
}

mixin template BlockPluginCommonImpl()
{
	private BlockManager bm;
	auto dbKey = IoKey("voxelman.block.block_mapping");

	override void registerResourceManagers(void delegate(IResourceManager) registerHandler)
	{
		registerHandler(bm = new BlockManager);
	}

	BlockInfoTable getBlocks()
	{
		return bm.getBlocks;
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
		clientWorld.idMapManager.regIdMapHandler(dbKey.str, &handleBlockMap);
	}

	void handleBlockMap(string[] blocks)
	{
		bm.blockMapping.setMapping(blocks);
	}
}

final class BlockPluginServer : IPlugin
{
	mixin BlockPluginCommonImpl;
	// IPlugin stuff
	mixin IdAndSemverFrom!(voxelman.block.plugininfo);

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto ioman = resmanRegistry.getResourceManager!IoManager;
		ioman.registerWorldLoadSaveHandlers(&readBlockMap, &writeBlockMap);
	}

	override void init(IPluginManager pluginman)
	{
		auto serverWorld = pluginman.getPlugin!ServerWorld;
		serverWorld.idMapManager.regIdMap(dbKey.str, bm.blockMapping.nameRange.array);
	}

	void readBlockMap(ref PluginDataLoader loader)
	{
		loader.readMapping(dbKey, bm.blockMapping);
	}

	void writeBlockMap(ref PluginDataSaver saver)
	{
		saver.writeMapping(dbKey, bm.blockMapping);
	}
}
