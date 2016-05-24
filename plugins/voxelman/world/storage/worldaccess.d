/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.worldaccess;

import std.experimental.logger;
import voxelman.core.config;
import voxelman.world.storage.chunk;
import voxelman.world.storage.chunkmanager;
import voxelman.world.storage.coordinates;

final class WorldAccess
{
	private ChunkManager chunkManager;
	private ChunkChangeManager chunkChangeManager;

	this(ChunkManager chunkManager, ChunkChangeManager chunkChangeManager) {
		this.chunkManager = chunkManager;
		this.chunkChangeManager = chunkChangeManager;
	}

	bool setBlock(BlockWorldPos bwp, BlockId blockId) {
		auto blockIndex = BlockChunkIndex(bwp);
		auto chunkPos = ChunkWorldPos(bwp);
		BlockId[] blocks = chunkManager.getWriteBuffer(chunkPos, FIRST_LAYER);
		if (blocks is null)
			return false;
		blocks[blockIndex] = blockId;

		import std.range : only;
		chunkChangeManager.onBlockChanges(chunkPos, only(BlockChange(blockIndex.index, blockId)), FIRST_LAYER);
		return true;
	}

	BlockId getBlock(BlockWorldPos bwp) {
		auto blockIndex = BlockChunkIndex(bwp);
		auto chunkPos = ChunkWorldPos(bwp);
		auto snap = chunkManager.getChunkSnapshot(chunkPos, FIRST_LAYER);
		if (!snap.isNull) {
			return snap.getBlockId(blockIndex);
		}
		return 0;
	}

	bool isFree(BlockWorldPos bwp) {
		 return getBlock(bwp) < 2; // air or unknown
	}
}
