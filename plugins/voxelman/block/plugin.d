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
		regBlock("unknown").color(0,0,0).isVisible(false).solidity(Solidity.solid).meshHandler(&makeNullMesh);
		regBlock("air").color(0,0,0).isVisible(false).solidity(Solidity.transparent).meshHandler(&makeNullMesh);
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
		bm.regBlock("water").colorHex(0x0055AA).meshHandler(&makeColoredBlockMesh).solidity(Solidity.semiTransparent);
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
