/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.client.chunkmeshman;

import std.experimental.logger;
import std.concurrency : Tid, thisTid, send, receiveTimeout;
import std.datetime : msecs;

import voxelman.client.chunkman;
import voxelman.block.blockman;
import voxelman.core.chunkmesh;
import voxelman.core.config;
import voxelman.core.meshgen;
import voxelman.storage.chunk;
import voxelman.storage.coordinates;
import voxelman.utils.queue;
import voxelman.utils.workergroup;
import voxelman.utils.hashset;


///
struct ChunkMeshMan
{
	WorkerGroup!(meshWorkerThread) meshWorkers;

	ChunkChange[ChunkWorldPos] chunkChanges;

	Queue!(Chunk*) changedChunks;
	Queue!(Chunk*) chunksToMesh;
	Queue!(Chunk*) dirtyChunks;
	HashSet!ChunkWorldPos visibleChunks;

	size_t numMeshChunkTasks;
	size_t numDirtyChunksPending;

	BlockMan* blockMan;
	ChunkMan* chunkMan;

	void init(ChunkMan* _chunkMan, BlockMan* _blockMan, uint numWorkers)
	{
		chunkMan = _chunkMan;
		blockMan = _blockMan;
		meshWorkers.startWorkers(numWorkers, thisTid, blockMan.blocks);
	}

	void stop()
	{
		meshWorkers.stopWorkers();
	}

	void update()
	{
		bool message = true;
		while (message)
		{
			message = receiveTimeout(0.msecs,
				(immutable(MeshGenResult)* data){onMeshLoaded(cast(MeshGenResult*)data);}
				);
		}

		startMeshUpdateCycle();
		applyChunkChanges();
		meshChunks();
		processDirtyChunks();
	}

	void onChunkLoaded(Chunk* chunk, BlockData blockData)
	{
		// full chunk update
		if (chunk.isLoaded)
		{
			infof("full chunk change %s", chunk.position);
			// if there was previous changes they do not matter anymore
			chunkChanges[chunk.position] = ChunkChange(null, blockData);
			return;
		}

		//infof("chunk loaded %s data %s", chunk.position, blockData.blocks);

		chunk.isLoaded = true;

		++chunkMan.totalLoadedChunks;

		setChunkData(chunk, blockData);

		if (chunk.isVisible)
			tryMeshChunk(chunk);

		foreach(a; chunk.adjacent)
			if (a !is null) tryMeshChunk(a);
	}

	void setChunkData(Chunk* chunk, ref BlockData blockData)
	{
		chunk.isVisible = true;
		if (blockData.uniform)
		{
			chunk.isVisible = blockMan.blocks[blockData.uniformType].isVisible;
		}
		chunk.snapshot.blockData = blockData;
	}

	void onChunkChanged(Chunk* chunk, BlockChange[] changes)
	{
		//infof("partial chunk change %s", chunk.position);
		if (auto _changes = chunk.position in chunkChanges)
		{
			if (_changes.blockChanges is null)
			{
				// block changes applied on top of full chunk update
				_changes.newBlockData.applyChangesFast(changes);
			}
			else
			{
				// more changes added
				_changes.blockChanges ~= changes;
			}
		}
		else
		{
			// new changes arrived
			chunkChanges[chunk.position] = ChunkChange(changes);
		}
	}

	void onChunkRemoved(Chunk* chunk)
	{
		visibleChunks.remove(chunk.position);
		chunkChanges.remove(chunk.position);
		changedChunks.remove(chunk);
		chunksToMesh.remove(chunk);
		dirtyChunks.remove(chunk);
	}

	void tryMeshChunk(Chunk* chunk)
	{
		assert(chunk);
		if (chunk.needsMesh && chunk.canBeMeshed)
		{
			if (!surroundedBySolidChunks(chunk))
				meshChunk(chunk);
		}
	}

	bool surroundedBySolidChunks(Chunk* chunk)
	{
		import voxelman.block.block;
		foreach(i, a; chunk.adjacent)
		if (a !is null) {
			bool solidSide = a.snapshot.blockData.uniform &&
			blockMan.blocks[a.snapshot.blockData.uniformType]
				.isSideTransparent(cast(Side)oppSide[i]);
			if (!solidSide) return false;
		}
		return true;
	}

	void meshChunk(Chunk* chunk)
	{
		assert(chunk);

		++chunk.numReaders;
		foreach(a; chunk.adjacent)
			if (a !is null) ++a.numReaders;

		assert(chunk);
		assert(!chunk.hasWriter);
		foreach(a; chunk.adjacent)
		{
			assert(a !is null);
			assert(!a.hasWriter);
		}

		chunk.isMeshing = true;
		++numMeshChunkTasks;
		meshWorkers.nextWorker.send(cast(shared(Chunk)*)chunk);
	}

	void onMeshLoaded(MeshGenResult* data)
	{
		Chunk* chunk = chunkMan.getChunk(data.position);
		assert(chunk);

		chunk.isMeshing = false;

		// Allow chunk to be written or deleted.
		// TODO: that can break if chunks where added during meshing
		--chunk.numReaders;
		foreach(a; chunk.adjacent)
				if (a !is null) --a.numReaders;
		--numMeshChunkTasks;

		// Chunk is already in delete queue
		if (chunk.isMarkedForDeletion)
		{
			delete data.meshData;
			delete data;
			return;
		}

		//infof("mesh data loaded %s %s", data.position, data.meshData.length);

		// chunk was remeshed after change.
		// Mesh will be uploaded for all changed chunks at once in processDirtyChunks.
		if (chunk.isDirty)
		{
			chunk.isDirty = false;
			chunk.newMeshData = data.meshData;
			--numDirtyChunksPending;
		}
		else
			loadMeshData(chunk, data.meshData);
	}

	void loadMeshData(Chunk* chunk, ubyte[] meshData)
	{
		assert(chunk);
		// Attach mesh
		if (chunk.mesh is null)
			chunk.mesh = new ChunkMesh();
		chunk.mesh.data = meshData;

		ChunkWorldPos position = chunk.position;
		chunk.mesh.position = position.vector * CHUNK_SIZE;
		chunk.mesh.isDataDirty = true;
		chunk.isVisible = chunk.mesh.data.length > 0;
		chunk.hasMesh = true;

		if (chunk.isVisible)
			visibleChunks.put(chunk.position);

		//infof("Chunk mesh loaded at %s, length %s", chunk.position, chunk.mesh.data.length);
	}

	/// Checks if there is any chunks that have changes
	/// Starts new mesh update cycle if previous one was completed.
	/// Adds changed chunks to changedChunks queue on new cycle start
	void startMeshUpdateCycle()
	{
		auto queuesEmpty = changedChunks.empty &&
			chunksToMesh.empty && dirtyChunks.empty;

		if (!queuesEmpty || chunkChanges.length == 0)
			return;

		trace("startMeshUpdateCycle");

		foreach(pair; chunkChanges.byKeyValue)
		{
			Chunk** chunkPtr = pair.key in chunkMan.chunks;
			if (chunkPtr is null || (**chunkPtr).isMarkedForDeletion || (*chunkPtr) is null)
			{
				chunkChanges.remove(pair.key);
				continue;
			}

			Chunk* chunk = *chunkPtr;
			assert(chunk);

			chunk.change = pair.value;
			chunk.hasUnappliedChanges = true;
			changedChunks.put(chunk);
			chunkChanges.remove(pair.key);
		}

		chunkChanges = null;
	}

	/// Applies changes to chunks
	/// Calculates affected chunks and adds them to chunksToMesh queue
	void applyChunkChanges()
	{
		foreach(queueItem; changedChunks)
		{
			Chunk* chunk = queueItem.value;
			if (chunk is null)
			{
				queueItem.remove();
				continue;
			}
			assert(chunk);

			void addAdjacentChunks()
			{
				foreach(a; chunk.adjacent)
				{
					if (a && a.canBeMeshed)
						chunksToMesh.put(a);
				}
			}

			if (!chunk.isUsed)
			{
				bool blocksChanged = false;
				// apply changes
				if (chunk.change.blockChanges is null)
				{
					// full chunk update
					setChunkData(chunk, chunk.change.newBlockData);
					// TODO remove mesh if not visible
					addAdjacentChunks();
					blocksChanged = true;

					infof("applying full update to %s", chunk.position);
				}
				else
				{
					// partial update
					ushort[2] changedBlocksRange = chunk
						.snapshot
						.blockData
						.applyChanges(chunk.change.blockChanges);

					// blocks was changed
					if (changedBlocksRange[0] != changedBlocksRange[1])
					{
						addAdjacentChunks();
						blocksChanged = true;
					}
					//infof("applying block changes to %s", chunk.position);
					ubyte bx, by, bz;
					foreach(change; chunk.change.blockChanges)
					{
						bx = change.index & CHUNK_SIZE_BITS;
						by = (change.index / CHUNK_SIZE_SQR) & CHUNK_SIZE_BITS;
						bz = (change.index / CHUNK_SIZE) & CHUNK_SIZE_BITS;
						tracef("i %s | x %s y %s z %s | wx %s wy %s wz %s | b %s; ",
							change.index,
							bx,
							by,
							bz,
							bx + chunk.position.x * CHUNK_SIZE,
							by + chunk.position.y * CHUNK_SIZE,
							bz + chunk.position.z * CHUNK_SIZE,
							change.blockId);
					}
				}

				chunk.change = ChunkChange.init;

				//infof("canBeMeshed %s, blocksChanged %s", chunk.canBeMeshed, blocksChanged);
				if (chunk.canBeMeshed && blocksChanged)
				{
					assert(chunk);
					chunksToMesh.put(chunk);
				}

				chunk.hasUnappliedChanges = false;

				queueItem.remove();
			}
		}
	}

	/// Sends chunks from chunksToMesh queue to mesh worker and moves them
	/// to dirtyChunks queue
	void meshChunks()
	{
		foreach(queueItem; chunksToMesh)
		{
			Chunk* chunk = queueItem.value;
			if (chunk is null)
			{
				queueItem.remove();
				continue;
			}
			assert(chunk);

			// chunks adjacent to the modified one may still be in use
			if (!chunk.isUsed && !chunk.adjacentHasUnappliedChanges)
			{
				meshChunk(chunk);
				++numDirtyChunksPending;
				queueItem.remove();
			}
		}
	}

	///
	void processDirtyChunks()
	{
		auto queuesEmpty = changedChunks.empty && chunksToMesh.empty;

		// swap meshes when all chunks are meshed
		if (queuesEmpty && numDirtyChunksPending == 0)
		{
			foreach(chunk; dirtyChunks.valueRange)
			{
				loadMeshData(chunk, chunk.newMeshData);
				chunk.newMeshData = null;
			}
		}
	}
}
