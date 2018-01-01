/**
Copyright: Copyright (c) 2016-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.block.plugin;

import voxelman.graphics;
import voxelman.log;
import voxelman.math;
import std.array : array;
import cbor;
import pluginlib;
import voxelman.core.config : BlockId;
import voxelman.world.storage;
import voxelman.world.block;
import voxelman.utils.mapping;
import voxelman.globalconfig;

import voxelman.world.serverworld;
import voxelman.world.clientworld;

enum TEX_TILE_SIZE = 32;
enum TEX_TILE_SIZE_VEC = ivec2(TEX_TILE_SIZE, TEX_TILE_SIZE);

final class BlockManager : IResourceManager
{
private:
	Mapping!BlockInfo blockMapping;

public:
	override string id() @property { return "voxelman.block.blockmanager"; }
	override void preInit()
	{
		regBaseBlocks(&regBlock);
		sideTable = sideIntersectionTable(NUM_SIDE_MASKS);
		setSideTable(sideTable);
	}

	BlockInfoSetter regBlock(string name)
	{
		size_t id = blockMapping.put(BlockInfo(name));
		assert(id <= BlockId.max);
		return BlockInfoSetter(&blockMapping, id);
	}

	BlockInfoTable getBlocks()
	{
		return BlockInfoTable(cast(immutable)blockMapping.infoArray, sideTable);
	}

	// returns size_t.max if not found
	size_t getId(string name)
	{
		return blockMapping.id(name);
	}

	SideIntersectionTable sideTable;
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
	mixin IdAndSemverFrom!"voxelman.block.plugininfo";
	TextureAtlas texAtlas;

	override void preInit()
	{
		texAtlas = new TextureAtlas(256);
	}

	override void init(IPluginManager pluginman)
	{
		auto clientWorld = pluginman.getPlugin!ClientWorld;
		clientWorld.idMapManager.regIdMapHandler(dbKey.str, &handleBlockMap);
		loadTextures();
	}

	void loadTextures()
	{
		// fill 0 texture with white color
		texAtlas.insert(TEX_TILE_SIZE_VEC, Color4ub(255, 255, 255));

		SpriteRef[string] texMap = loadNamedSpriteSheet(BUILD_TO_ROOT_PATH~"res/tex/blocks", texAtlas, TEX_TILE_SIZE_VEC);

		Sprite sprite;
		SpriteRef missingTexture = texMap.get("missing-texture", null);

		if (missingTexture is null)
		{
			ivec2 atlasPos = texAtlas.insert(TEX_TILE_SIZE_VEC, Color4ub(0, 255, 255));
			sprite.atlasRect = irect(atlasPos, TEX_TILE_SIZE_VEC);
			missingTexture = &sprite;
		}

		irect getAtlasRect(string name) {
			return texMap.get(name, missingTexture).atlasRect;
		}

		foreach(ref BlockInfo binfo; bm.blockMapping.infoArray)
		{
			irect rect = getAtlasRect(binfo.name);
			ubyte[2] uv = [cast(ubyte)(rect.x / TEX_TILE_SIZE), cast(ubyte)(rect.y / TEX_TILE_SIZE)];
			binfo.uv = uv;
			infof("%s uv: %s", binfo.name, uv);
		}
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
	mixin IdAndSemverFrom!"voxelman.block.plugininfo";

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto ioman = resmanRegistry.getResourceManager!IoManager;
		ioman.registerWorldLoadSaveHandlers(&readBlockMap, &writeBlockMap);
	}

	override void init(IPluginManager pluginman)
	{
		auto serverWorld = pluginman.getPlugin!ServerWorld;
		serverWorld.idMapManager.regIdMapHandler(dbKey.str, () => bm.blockMapping.nameRange.array);
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
