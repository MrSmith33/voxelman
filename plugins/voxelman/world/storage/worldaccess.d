/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.worldaccess;

import voxelman.log;
import std.string;
import voxelman.geometry.box;
import voxelman.core.config;
import voxelman.block.utils;
import voxelman.world.storage;

final class WorldAccess
{
	private ChunkManager chunkManager;
	BlockInfoTable blockInfos;
	BlockChange[][ChunkWorldPos] blockChanges;

	this(ChunkManager chunkManager) {
		this.chunkManager = chunkManager;
	}

	// TODO move out change management
	import std.range : isInputRange, array;
	void onBlockChange(ChunkWorldPos cwp, BlockChange change)
	{
		blockChanges[cwp] = blockChanges.get(cwp, null) ~ change;
	}

	void applyBlockChanges(ChunkWorldPos cwp, BlockChange[] changes)
	{
		WriteBuffer* writeBuffer = chunkManager.getOrCreateWriteBuffer(cwp,
				FIRST_LAYER, WriteBufferPolicy.copySnapshotArray);
		if (writeBuffer is null) return;
		applyChanges(writeBuffer, changes);
		writeBuffer.layer.metadata = calcChunkFullMetadata(writeBuffer.layer, blockInfos);
	}

	bool setBlock(BlockWorldPos bwp, BlockId blockId) {
		auto blockIndex = BlockChunkIndex(bwp);
		auto cwp = ChunkWorldPos(bwp);
		WriteBuffer* writeBuffer = chunkManager.getOrCreateWriteBuffer(cwp,
				FIRST_LAYER, WriteBufferPolicy.copySnapshotArray);
		if (writeBuffer is null) return false;

		BlockId[] blocks = writeBuffer.layer.getArray!BlockId;
		blocks[blockIndex] = blockId;
		onBlockChange(cwp, BlockChange(blockIndex.index, blockId));
		updateWriteBufferMetadata(writeBuffer);
		return true;
	}

	bool fillBox(WorldBox blockFillBox, BlockId blockId) {
		WorldBox affectedChunks = blockBoxToChunkBox(blockFillBox);
		ushort dimension = blockFillBox.dimension;

		foreach(chunkPos; affectedChunks.positions) {
			Box chunkBlockBox = chunkToBlockBox(chunkPos);
			auto intersection = boxIntersection(chunkBlockBox, blockFillBox);
			assert(!intersection.empty);

			auto cwp = ChunkWorldPos(chunkPos, dimension);
			auto chunkLocalBox = intersection;
			chunkLocalBox.position -= chunkBlockBox.position;

			fillChunkBox(cwp, chunkLocalBox, blockId);
		}
		return true;
	}

	// blockBox is in chunk-local coordinates
	bool fillChunkBox(ChunkWorldPos cwp, Box blockBox, BlockId blockId) {
		auto old = chunkManager.getChunkSnapshot(cwp, FIRST_LAYER);
		if (old.isNull) return false;

		if (old.type == StorageType.uniform)
		{
			if (old.getUniform!BlockId() == blockId) {
				return false;
			}
		}

		WriteBuffer* writeBuffer;

		// uniform fill
		if (blockBox.size == CHUNK_SIZE_VECTOR)
		{
			writeBuffer = chunkManager.getOrCreateWriteBuffer(cwp, FIRST_LAYER);
			if (writeBuffer is null) return false;
			writeBuffer.makeUniform!BlockId(blockId);
		}
		else
		{
			writeBuffer = chunkManager.getOrCreateWriteBuffer(cwp,
				FIRST_LAYER, WriteBufferPolicy.copySnapshotArray);
			BlockId[] blocks = writeBuffer.layer.getArray!BlockId;
			assert(blocks.length == CHUNK_SIZE_CUBE, format("blocks %s", blocks.length));
			setSubArray(blocks, blockBox, blockId);
		}
		updateWriteBufferMetadata(writeBuffer);

		return true;
	}

	private void updateWriteBufferMetadata(WriteBuffer* writeBuffer) {
		writeBuffer.layer.metadata = calcChunkFullMetadata(writeBuffer.layer, blockInfos);
	}

	BlockId getBlock(BlockWorldPos bwp) {
		auto blockIndex = BlockChunkIndex(bwp);
		auto chunkPos = ChunkWorldPos(bwp);
		auto snap = chunkManager.getChunkSnapshot(chunkPos, FIRST_LAYER, Yes.Uncompress);
		if (!snap.isNull) {
			return snap.getBlockId(blockIndex);
		}
		return 0;
	}

	bool isFree(BlockWorldPos bwp) {
		auto blockId = getBlock(bwp);
		return blockId == 1; // air
	}
}
