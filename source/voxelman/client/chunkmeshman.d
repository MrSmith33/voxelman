/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.client.chunkmeshman;

import std.concurrency : Tid, thisTid, send, receiveTimeout;
import std.datetime : msecs;
import std.stdio : writef, writeln, writefln;

import voxelman.blockman;
import voxelman.client.chunkman;
import voxelman.chunk;
import voxelman.chunkmesh;
import voxelman.config;
import voxelman.meshgen;
import voxelman.utils.queue;
import voxelman.utils.workergroup;


///
struct ChunkMeshMan
{
	WorkerGroup!(meshWorkerThread) meshWorkers;

	ChunkChange[ivec3] chunkChanges;

	Queue!(Chunk*) changedChunks;
	Queue!(Chunk*) chunksToMesh;
	Queue!(Chunk*) dirtyChunks;

	size_t numMeshChunkTasks;
	size_t numDirtyChunksPending;

	BlockMan* blockMan;
	ChunkMan* chunkMan;

	void init(ChunkMan* _chunkMan, BlockMan* _blockMan)
	{
		chunkMan = _chunkMan;
		blockMan = _blockMan;
		meshWorkers.startWorkers(NUM_WORKERS, thisTid, blockMan.blocks);
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

	void onChunkLoaded(Chunk* chunk, ChunkData chunkData)
	{
		// full chunk update
		if (chunk.isLoaded)
		{
			// if there was previous changes they do not matter anymore
			chunkChanges[chunk.coord] = ChunkChange(null, chunkData);
			return;
		}

		chunk.isLoaded = true;

		++chunkMan.totalLoadedChunks;

		setChunkData(chunk, chunkData);

		if (chunk.isVisible)
			tryMeshChunk(chunk);

		foreach(a; chunk.adjacent)
			if (a !is null) tryMeshChunk(a);
	}

	void setChunkData(Chunk* chunk, ref ChunkData chunkData)
	{
		chunk.isVisible = true;
		if (chunkData.uniform)
		{
			chunk.isVisible = blockMan.blocks[chunkData.uniformType].isVisible;
		}
		chunk.data = chunkData;
	}

	void onChunkChanged(Chunk* chunk, BlockChange[] changes)
	{
		if (auto _changes = chunk.coord in chunkChanges)
		{
			if (_changes.blockChanges is null)
			{
				// block changes applied on top of full chunk update
				_changes.newChunkData.applyChanges(changes);
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
			chunkChanges[chunk.coord] = ChunkChange(changes);
		}
	}

	void onChunkRemoved(Chunk* chunk)
	{
		chunkChanges.remove(chunk.coord);
		changedChunks.remove(chunk);
		chunksToMesh.remove(chunk);
		dirtyChunks.remove(chunk);
	}

	void tryMeshChunk(Chunk* chunk)
	{
		assert(chunk);
		if (chunk.needsMesh && chunk.canBeMeshed)
		{
			meshChunk(chunk);
		}
	}

	void meshChunk(Chunk* chunk)
	{
		assert(chunk);

		++chunk.numReaders;
		foreach(a; chunk.adjacent)
			if (a !is null) ++a.numReaders;

		chunk.isMeshing = true;
		++numMeshChunkTasks;
		meshWorkers.nextWorker.send(cast(shared(Chunk)*)chunk);
	}

	void onMeshLoaded(MeshGenResult* data)
	{
		Chunk* chunk = chunkMan.getChunk(data.coord);
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

		writefln("mesh data loaded %s %s", data.coord, data.meshData.length);

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

		ivec3 coord = chunk.coord;
		chunk.mesh.position = vec3(coord.x, coord.y, coord.z) * CHUNK_SIZE - 0.5f;
		chunk.mesh.isDataDirty = true;
		chunk.isVisible = chunk.mesh.data.length > 0;
		chunk.hasMesh = true;

		//writefln("Chunk mesh generated at %s", chunk.coord);
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

		writefln("startMeshUpdateCycle");

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
					setChunkData(chunk, chunk.change.newChunkData);
					// TODO remove mesh if not visible
					addAdjacentChunks();
					blocksChanged = true;

					writefln("applying full update to %s", chunk.coord);
				}
				else
				{
					// partial update
					ushort[2] changedBlocksRange = chunk.data.applyChanges(chunk.change.blockChanges);

					// blocks was changed
					if (changedBlocksRange[0] != changedBlocksRange[1])
					{
						addAdjacentChunks();
						blocksChanged = true;
					}
					writefln("applying block changes to %s", chunk.coord);
				}

				chunk.change = ChunkChange.init;

				if (chunk.canBeMeshed && chunk.isVisible && blocksChanged)
					chunksToMesh.put(chunk);

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
