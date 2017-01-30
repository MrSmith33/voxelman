/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.worldaccess;

import voxelman.log;
import std.string;
import voxelman.geometry.box;
import voxelman.core.config;
import voxelman.world.block;
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

	bool isChunkLoaded(ChunkWorldPos cwp) {
		return chunkManager.isChunkLoaded(cwp);
	}

	void applyBlockChanges(ChunkWorldPos cwp, BlockChange[] changes)
	{
		WriteBuffer* writeBuffer = chunkManager.getOrCreateWriteBuffer(cwp,
				BLOCK_LAYER, WriteBufferPolicy.copySnapshotArray);
		if (writeBuffer is null) return;
		applyChanges(writeBuffer, changes);
		writeBuffer.layer.metadata = calcChunkFullMetadata(writeBuffer.layer, blockInfos);
	}

	bool setBlock(BlockWorldPos bwp, BlockId blockId, BlockMetadata blockMeta = 0) {
		auto blockIndex = BlockChunkIndex(bwp);
		auto cwp = ChunkWorldPos(bwp);
		WriteBuffer* writeBuffer = chunkManager.getOrCreateWriteBuffer(cwp,
				BLOCK_LAYER, WriteBufferPolicy.copySnapshotArray);
		if (writeBuffer is null) return false;

		BlockId[] blocks = writeBuffer.layer.getArray!BlockId;
		blocks[blockIndex] = blockId;
		onBlockChange(cwp, BlockChange(blockIndex.index, blockId, blockMeta));
		updateWriteBufferMetadata(writeBuffer);
		return true;
	}

	bool fillBox(WorldBox blockFillBox, BlockId blockId, BlockMetadata blockMeta = 0) {
		WorldBox affectedChunks = blockBoxToChunkBox(blockFillBox);
		ushort dimension = blockFillBox.dimension;

		foreach(chunkPos; affectedChunks.positions) {
			Box chunkBlockBox = chunkToBlockBox(chunkPos);
			auto intersection = boxIntersection(chunkBlockBox, blockFillBox);
			assert(!intersection.empty);

			auto cwp = ChunkWorldPos(chunkPos, dimension);
			auto chunkLocalBox = intersection;
			chunkLocalBox.position -= chunkBlockBox.position;

			fillChunkBox(cwp, chunkLocalBox, blockId, blockMeta);
		}
		return true;
	}

	// blockBox is in chunk-local coordinates
	bool fillChunkBox(ChunkWorldPos cwp, Box blockBox, BlockId blockId, BlockMetadata blockMeta = 0) {
		auto oldBlocks = chunkManager.getChunkSnapshot(cwp, BLOCK_LAYER);
		if (oldBlocks.isNull) return false;

		if (oldBlocks.type == StorageType.uniform)
		{
			if (oldBlocks.getUniform!BlockId() == blockId) {
				return false;
			}
		}

		WriteBuffer* blockWB;

		// uniform fill
		if (blockBox.size == CHUNK_SIZE_VECTOR)
		{
			blockWB = chunkManager.getOrCreateWriteBuffer(cwp, BLOCK_LAYER);
			if (blockWB is null) return false;
			blockWB.makeUniform!BlockId(blockId);
		}
		else
		{
			blockWB = chunkManager.getOrCreateWriteBuffer(cwp,
				BLOCK_LAYER, WriteBufferPolicy.copySnapshotArray);
			BlockId[] blocks = blockWB.getArray!BlockId;
			assert(blocks.length == CHUNK_SIZE_CUBE, format("blocks %s", blocks.length));
			setSubArray(blocks, CHUNK_SIZE_VECTOR, blockBox, blockId);
		}
		fillChunkBoxMetadata(cwp, blockBox, blockMeta);
		updateWriteBufferMetadata(blockWB);

		return true;
	}

	private void fillChunkBoxMetadata(ChunkWorldPos cwp, Box blockBox, BlockMetadata blockMeta) {
		auto oldMetas = chunkManager.getChunkSnapshot(cwp, METADATA_LAYER);

		if (oldMetas.type == StorageType.uniform)
		{
			if (oldMetas.getUniform!BlockMetadata == blockMeta) {
				return;
			}
		}

		if (blockBox.size == CHUNK_SIZE_VECTOR)
		{
			WriteBuffer* metadataWB = chunkManager.getOrCreateWriteBuffer(cwp, METADATA_LAYER);
			metadataWB.makeUniform!BlockMetadata(blockMeta);
			if (blockMeta == 0) {
				metadataWB.removeSnapshot = true;
			}
		}
		else
		{
			WriteBuffer* metadataWB = chunkManager.getOrCreateWriteBuffer(cwp,
				METADATA_LAYER, WriteBufferPolicy.copySnapshotArray);
			assert(metadataWB.layer.type == StorageType.fullArray);
			BlockMetadata[] metas = metadataWB.getArray!BlockMetadata;
			assert(metas.length == CHUNK_SIZE_CUBE, format("metas %s", metas.length));
			setSubArray(metas, CHUNK_SIZE_VECTOR, blockBox, blockMeta);
		}
	}

	private void updateWriteBufferMetadata(WriteBuffer* writeBuffer) {
		writeBuffer.layer.metadata = calcChunkFullMetadata(writeBuffer.layer, blockInfos);
	}

	BlockId getBlock(BlockWorldPos bwp) {
		auto blockIndex = BlockChunkIndex(bwp);
		auto chunkPos = ChunkWorldPos(bwp);
		auto snap = chunkManager.getChunkSnapshot(chunkPos, BLOCK_LAYER, Yes.Uncompress);
		if (!snap.isNull) {
			return snap.getBlockId(blockIndex);
		}
		return 0;
	}

	BlockMetadata getBlockMeta(BlockWorldPos bwp) {
		auto blockIndex = BlockChunkIndex(bwp);
		auto chunkPos = ChunkWorldPos(bwp);
		auto snap = chunkManager.getChunkSnapshot(chunkPos, METADATA_LAYER, Yes.Uncompress);
		if (!snap.isNull) {
			return snap.getLayerItemNoncompressed!BlockMetadata(blockIndex);
		}
		return 0;
	}

	BlockIdAndMeta getBlockIdAndMeta(BlockWorldPos bwp) {
		BlockIdAndMeta result;
		auto blockIndex = BlockChunkIndex(bwp);
		auto chunkPos = ChunkWorldPos(bwp);

		auto blocks = chunkManager.getChunkSnapshot(chunkPos, BLOCK_LAYER, Yes.Uncompress);
		if (!blocks.isNull) {
			result.id = blocks.getBlockId(blockIndex);
		}

		auto metas = chunkManager.getChunkSnapshot(chunkPos, METADATA_LAYER, Yes.Uncompress);
		if (!metas.isNull) {
			result.metadata = metas.getLayerItemNoncompressed!BlockMetadata(blockIndex);
		}

		return result;
	}

	bool isFree(BlockWorldPos bwp) {
		auto blockId = getBlock(bwp);
		return blockId == 1; // air
	}
}
