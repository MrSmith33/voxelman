/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.storage.worldaccess;

import std.experimental.logger;
import voxelman.config;
import voxelman.storage.chunk;
import voxelman.storage.coordinates;
import voxelman.storage.utils;
import voxelman.storage.world;

/// When modifying world through WorldAccess
/// changes will automatically proparate to client each tick
struct WorldAccess
{
	this(Chunk* delegate(ChunkWorldPos) chunkGetter,
		TimestampType delegate() timestampGetter)
	{
		this.chunkGetter = chunkGetter;
		assert(chunkGetter);
		this.timestampGetter = timestampGetter;
		assert(timestampGetter);
	}
	@disable this();

	BlockType getBlock(BlockWorldPos blockPos)
	{
		ChunkWorldPos chunkPos = ChunkWorldPos(blockPos);
		Chunk* chunk = chunkGetter(chunkPos);
		if (chunk)
		{
			BlockDataSnapshot* snapshot = chunk.getReadableSnapshot(timestampGetter());
			if (snapshot)
			{
				auto blockIndex = BlockChunkIndex(blockPos);
				return snapshot.blockData.getBlockType(blockIndex);
			}
		}

		return 0; // unknown block. Indicates that chunk is not loaded.
	}

	bool setBlock(BlockWorldPos blockPos, BlockType blockType)
	{
		ChunkWorldPos chunkPos = ChunkWorldPos(blockPos);
		Chunk* chunk = chunkGetter(chunkPos);

		if (chunk)
		{
			BlockDataSnapshot* snapshot = chunk.getWriteableSnapshot(timestampGetter());

			// chunk was not loaded yet
			if (snapshot is null)
				return false;

			auto blockIndex = BlockChunkIndex(blockPos);
			snapshot.blockData.setBlockType(blockIndex, blockType);

			foreach(handler; onChunkModifiedHandlers)
				handler(chunk, [BlockChange(blockIndex.index, blockType)]);

			return true;
		}
		else
			return false;
	}

	//bool isBlockLoaded(BlockWorldPos blockPos);
	//bool loadBlockRange(AABB aabb);
	TimestampType currentTimestamp() @property
	{
		return timestampGetter();
	}

	void delegate(Chunk*, BlockChange[])[] onChunkModifiedHandlers;
private:
	Chunk* delegate(ChunkWorldPos) chunkGetter;
	TimestampType delegate() timestampGetter;
}
