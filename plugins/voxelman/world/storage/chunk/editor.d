/**
Copyright: Copyright (c) 2017-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.chunk.editor;

import voxelman.container.hash.set;
import voxelman.core.config;
import voxelman.world.storage.chunk;
import voxelman.world.storage;


final class ChunkEditor
{
	private ubyte numLayers;
	private ChunkManager chunkManager;
	void delegate(ChunkWorldPos) addServerObserverHandler;
	void delegate(ChunkWorldPos) removeServerObserverHandler;

	private WriteBuffer[ChunkWorldPos][] writeBuffers;

	this(ubyte _numLayers, ChunkManager _chunkManager) {
		numLayers = _numLayers;
		writeBuffers.length = _numLayers;
		chunkManager = _chunkManager;
	}

	/// Returns all write buffers. You can modify data in write buffers, but not
	/// hashmap itself.
	/// Can be used for metadata update before commit.
	WriteBuffer[ChunkWorldPos] getWriteBuffers(ubyte layer) {
		return writeBuffers[layer];
	}

	/// called at the end of tick
	void commitSnapshots(TimestampType currentTime) {
		foreach(ubyte layer; 0..numLayers)
		{
			auto writeBuffersCopy = writeBuffers[layer];
			// Clear it here because commit can unload chunk.
			// And unload asserts that chunk is not in writeBuffers.
			writeBuffers[layer] = null;
			foreach(cwp, writeBuffer; writeBuffersCopy)
			{
				if (writeBuffer.isModified)
				{
					chunkManager.commitLayerSnapshot(cwp, writeBuffer, currentTime, layer);
				}
				else
				{
					freeLayerArray(writeBuffer.layer);
				}
				removeServerObserverHandler(cwp);
			}
		}
	}

	/// Returns writeable copy of current chunk snapshot.
	/// This buffer is valid until commit.
	/// After commit this buffer becomes next immutable snapshot.
	/// Returns null if chunk is not added and/or not loaded.
	/// If write buffer was not yet created then it is created based on policy.
	///
	/// If allowNonLoaded is enabled, then will create write buffer even if chunk is in non_loaded state.
	///   Useful for offline generation and conversion tools that write directly to chunk manager.
	///   You can write all chunk at once and then commit. Internal user will prevent write buffers from unloading.
	///   And on commit a save will be performed automatically.
	///
	/// BUG: returned pointer points inside hash table.
	///      If new write buffer is added hash table can reallocate.
	///      Do not create new write buffers while keeping pointer to any write buffer.
	///      Reallocation can prevent changes to buffers obtained earlier than reallocation to be invisible.
	WriteBuffer* getOrCreateWriteBuffer(ChunkWorldPos cwp, ubyte layer,
		WriteBufferPolicy policy = WriteBufferPolicy.createUniform,
		bool allowNonLoaded = false)
	{
		if (!chunkManager.isChunkLoaded(cwp) && !allowNonLoaded) return null;
		auto writeBuffer = cwp in writeBuffers[layer];
		if (writeBuffer is null) {
			writeBuffer = createWriteBuffer(cwp, layer);
			if (writeBuffer && policy == WriteBufferPolicy.copySnapshotArray) {
				auto old = chunkManager.getChunkSnapshot(cwp, layer);
				if (!old.isNull) {
					applyLayer(old, writeBuffer.layer);
				}
			}
		}
		return writeBuffer;
	}

	// Creates write buffer for writing changes in it.
	// Latest snapshot's data is not copied in it.
	// Write buffer is then avaliable through getWriteBuffer/getOrCreateWriteBuffer.
	// On commit stage WB is moved into new snapshot if write buffer was modified.
	// Adds internal user that is removed on commit to prevent chunk from unloading with uncommitted changes.
	// Returns pointer to created write buffer.
	private WriteBuffer* createWriteBuffer(ChunkWorldPos cwp, ubyte layer) {
		assert(cwp !in writeBuffers[layer]);
		auto wb = WriteBuffer.init;
		wb.layer.layerId = layer;
		wb.layer.dataLength = chunkManager.layerInfos[layer].uniformExpansionType;
		writeBuffers[layer][cwp] = wb;
		addServerObserverHandler(cwp); // prevent unload until commit
		return cwp in writeBuffers[layer];
	}
}
