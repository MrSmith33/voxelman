/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.block.plugin;

import std.array : Appender;
import pluginlib;
import voxelman.core.config : BlockId;
import voxelman.storage.coordinates;
import voxelman.block.utils;

shared static this()
{
	pluginRegistry.regClientPlugin(new BlockPlugin);
	pluginRegistry.regServerPlugin(new BlockPlugin);
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
}

final class BlockManager : IResourceManager
{
private:
	BlockId[string] blockMap;
	immutable(BlockInfo)[] blockInfos;

public:
	override string id() @property { return "voxelman.block.blockmanager"; }

	BlockId regBlock(string name, ubyte[3] color, bool isVisible,
		bool isTransparent, Meshhandler meshHandler)
	{
		BlockId newId = cast(BlockId)blockInfos.length;
		blockMap[name] = newId;
		blockInfos ~= BlockInfo(name, meshHandler, color, isVisible, isTransparent);
		return newId;
	}
}

final class BlockPlugin : IPlugin
{
	private BlockManager bm;
	// IPlugin stuff
	mixin IdAndSemverFrom!(voxelman.block.plugininfo);

	override void registerResourceManagers(void delegate(IResourceManager) registerHandler)
	{
		bm = new BlockManager;
		registerHandler(bm);
	}

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		bm.regBlock("unknown", [0,0,0], false, false, &makeNullMesh);
		bm.regBlock("air", [0,0,0], false, true, &makeNullMesh);
		bm.regBlock("grass", [0, 255, 0], true, false, &makeColoredBlockMesh);
		bm.regBlock("dirt", [120, 72, 0], true, false, &makeColoredBlockMesh);
		bm.regBlock("stone", [128, 128, 128], true, false, &makeColoredBlockMesh);
		bm.regBlock("sand", [225, 169, 95], true, false, &makeColoredBlockMesh);
	}

	immutable(BlockInfo)[] getBlocks()
	{
		return bm.blockInfos;
	}
}



