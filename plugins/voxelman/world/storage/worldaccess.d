/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.worldaccess;

import std.experimental.logger;
import voxelman.core.config;
import voxelman.block.utils;
import voxelman.world.storage.chunk;
import voxelman.world.storage.chunkmanager;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.volume;

final class WorldAccess
{
	private ChunkManager chunkManager;
	immutable(BlockInfo)[] blockInfos;
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
		writeBuffer.metadata = calcChunkFullMetadata(writeBuffer, blockInfos);
	}

	bool setBlock(BlockWorldPos bwp, BlockId blockId) {
		auto blockIndex = BlockChunkIndex(bwp);
		auto cwp = ChunkWorldPos(bwp);
		WriteBuffer* writeBuffer = chunkManager.getOrCreateWriteBuffer(cwp,
				FIRST_LAYER, WriteBufferPolicy.copySnapshotArray);
		if (writeBuffer is null) return false;

		writeBuffer.blocks[blockIndex] = blockId;
		onBlockChange(cwp, BlockChange(blockIndex.index, blockId));
		updateWriteBufferMetadata(writeBuffer);
		return true;
	}

	bool fillVolume(Volume blockFillVolume, BlockId blockId) {
		Volume affectedChunks = blockVolumeToChunkVolume(blockFillVolume);
		ushort dimention = blockFillVolume.dimention;

		foreach(chunkPos; affectedChunks.positions) {
			Volume chunkBlockVolume = chunkToBlockVolume(chunkPos, dimention);
			auto intersection = volumeIntersection(chunkBlockVolume, blockFillVolume);
			assert(!intersection.empty);

			auto cwp = ChunkWorldPos(chunkPos, dimention);
			auto chunkLocalVolume = intersection;
			chunkLocalVolume.position -= chunkBlockVolume.position;

			fillChunkVolume(cwp, chunkLocalVolume, blockId);
		}
		return true;
	}

	// blockVolume is in chunk-local coordinates
	bool fillChunkVolume(ChunkWorldPos cwp, Volume blockVolume, BlockId blockId) {
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
		if (blockVolume.size == CHUNK_SIZE_VECTOR)
		{
			writeBuffer = chunkManager.getOrCreateWriteBuffer(cwp, FIRST_LAYER);
			if (writeBuffer is null) return false;
			writeBuffer.makeUniform(blockId);
		}
		else
		{
			writeBuffer = chunkManager.getOrCreateWriteBuffer(cwp,
				FIRST_LAYER, WriteBufferPolicy.copySnapshotArray);
			setSubArray(writeBuffer.blocks, blockVolume, blockId);
		}
		updateWriteBufferMetadata(writeBuffer);

		return true;
	}

	private void updateWriteBufferMetadata(WriteBuffer* writeBuffer) {
		writeBuffer.metadata = calcChunkFullMetadata(writeBuffer, blockInfos);
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
