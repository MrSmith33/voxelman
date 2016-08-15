/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.client.chunkmeshman;

import std.experimental.logger;

import voxelman.math;
import voxelman.block.utils;
import voxelman.blockentity.utils;
import voxelman.core.chunkmesh;
import voxelman.core.config;
import voxelman.core.meshgen;
import voxelman.world.storage.chunk;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.chunkmanager;
import voxelman.utils.worker;
import voxelman.container.hashset;
import voxelman.utils.renderutils;


struct MeshingPass
{
	size_t chunksToMesh;
	size_t meshGroupId;
	void delegate(size_t chunksRemeshed) onDone;
	size_t chunksMeshed;
}

enum debug_wasted_meshes = true;
enum WAIT_FOR_EMPTY_QUEUES = false;
//version = DBG;

struct MeshGenResult
{
	MeshGenTaskType type;
	ChunkWorldPos cwp;
	MeshVertex[][2] meshes;
}

///
struct ChunkMeshMan
{
	shared WorkerGroup meshWorkers;

	ubyte[ChunkWorldPos] wastedMeshes;

	ChunkMesh[ChunkWorldPos][2] chunkMeshes;

	MeshGenResult[] newChunkMeshes;
	MeshingPass[] meshingPasses;
	size_t currentMeshGroupId;

	size_t numMeshChunkTasks;
	size_t totalMeshedChunks;
	size_t totalMeshes;
	long totalMeshDataBytes;

	ChunkManager chunkManager;
	BlockInfoTable blocks;
	BlockEntityInfoTable beInfos;

	void init(ChunkManager _chunkManager, BlockInfoTable _blocks, BlockEntityInfoTable _beInfos, uint numMeshWorkers)
	{
		chunkManager = _chunkManager;
		blocks = _blocks;
		beInfos = _beInfos;
		meshWorkers.startWorkers(numMeshWorkers, &meshWorkerThread, blocks, beInfos);
	}

	void stop()
	{
		static if (WAIT_FOR_EMPTY_QUEUES)
		{
			while (!meshWorkers.queuesEmpty())
			{
				update();
			}
		}
		meshWorkers.stop();
	}

	void remeshChangedChunks(HashSet!ChunkWorldPos modifiedChunks,
		void delegate(size_t chunksRemeshed) onDone = null)
	{
		if (modifiedChunks.length == 0) return;

		size_t numMeshed;
		foreach(cwp; modifiedChunks.items)
		{
			if (meshChunk(cwp))
				++numMeshed;
		}

		if (numMeshed == 0) return;

		meshingPasses ~= MeshingPass(numMeshed, currentMeshGroupId, onDone);
		++currentMeshGroupId;
	}

	void update()
	{
		if (meshingPasses.length == 0) return;

		foreach(ref w; meshWorkers.workers)
		{
			while(!w.resultQueue.empty)
			{
				bool breakLoop = receiveTaskResult(w);
				if (breakLoop) break;
			}
		}

		commitMeshes();
	}

	bool receiveTaskResult(ref shared Worker w)
	{
		auto taskHeader = w.resultQueue.peekItem!MeshGenTaskHeader();

		// Process only current meshing pass. Leave next passes for later.
		if (taskHeader.meshGroupId != meshingPasses[0].meshGroupId)
		{
			//infof("meshGroup %s != %s", taskHeader.meshGroupId, meshingPasses[0].meshGroupId);
			return true;
		}

		++meshingPasses[0].chunksMeshed;
		--numMeshChunkTasks;

		w.resultQueue.dropItem!MeshGenTaskHeader();

		if (taskHeader.type == MeshGenTaskType.genMesh)
		{
			MeshVertex[][2] meshes = w.resultQueue.popItem!(MeshVertex[][2])();
			uint[7] blockTimestamps = w.resultQueue.popItem!(uint[7])();
			uint[7] entityTimestamps = w.resultQueue.popItem!(uint[7])();

			// Remove users
			ChunkWorldPos[7] positions;
			positions[0..6] = adjacentPositions(taskHeader.cwp);
			positions[6] = taskHeader.cwp;
			foreach(i, pos; positions)
			{
				chunkManager.removeSnapshotUser(pos, blockTimestamps[i], FIRST_LAYER);
				chunkManager.removeSnapshotUser(pos, entityTimestamps[i], ENTITY_LAYER);
			}

			// save result for later. All new meshes are loaded at once to prevent holes in geometry.
			newChunkMeshes ~= MeshGenResult(taskHeader.type, taskHeader.cwp, meshes);

			// Remove root, added on chunk load and gen.
			// Data can be collected by GC if no-one is referencing it.
			import core.memory : GC;
			if (meshes[0].ptr) GC.removeRoot(meshes[0].ptr); // TODO remove when moved to non-GC allocator
			if (meshes[1].ptr) GC.removeRoot(meshes[1].ptr); //
		}
		else // taskHeader.type == MeshGenTaskType.unloadMesh
		{
			// even mesh deletions are saved in a queue.
			newChunkMeshes ~= MeshGenResult(taskHeader.type, taskHeader.cwp);
		}

		return false;
	}

	void commitMeshes()
	{
		import std.algorithm : remove, SwapStrategy;
		if (meshingPasses[0].chunksMeshed != meshingPasses[0].chunksToMesh) return;

		foreach(meshResult; newChunkMeshes)
		{
			if (meshResult.type == MeshGenTaskType.genMesh)
			{
				loadMeshData(meshResult.cwp, meshResult.meshes);
			}
			else // taskHeader.type == MeshGenTaskType.unloadMesh
			{
				unloadChunkMesh(meshResult.cwp);
			}
		}
		newChunkMeshes.length = 0;
		newChunkMeshes.assumeSafeAppend();
		if (meshingPasses[0].onDone)
			meshingPasses[0].onDone(meshingPasses[0].chunksToMesh);
		meshingPasses = remove!(SwapStrategy.stable)(meshingPasses, 0);
		meshingPasses.assumeSafeAppend();
	}

	void drawDebug(ref Batch debugBatch)
	{
		static if (debug_wasted_meshes)
		foreach(cwp; wastedMeshes.byKey)
		{
			vec3 blockPos = cwp.vector * CHUNK_SIZE;
			debugBatch.putCube(blockPos + CHUNK_SIZE/2-1, vec3(4,4,4), Colors.red, false);
		}
	}

	void onChunkRemoved(ChunkWorldPos cwp)
	{
		unloadChunkMesh(cwp);
		static if (debug_wasted_meshes)
		{
			wastedMeshes.remove(cwp);
		}
	}

	bool producesMesh(ChunkSnapWithAdjacent snapWithAdjacent)
	{
		import voxelman.block.utils;

		Solidity solidity;
		bool singleSolidity = hasSingleSolidity(snapWithAdjacent.centralSnapshot.metadata, solidity);

		if (singleSolidity)
		{
			// completely transparent chunks do not produce meshes.
			if (solidity == Solidity.transparent) {
				return false;
			}

			foreach(Side side, adj; snapWithAdjacent.adjacentSnapshots)
			{
				Solidity adjSideSolidity = chunkSideSolidity(adj.metadata, oppSide[side]);
				if (solidity.isMoreSolidThan(adjSideSolidity)) return true;
			}

			// uniformly solid chunk is surrounded by blocks with the same of higher solidity.
			// so mesh will not be produced.
			return false;
		}
		else
		{
			// on borders between different solidities mesh is present.
			return true;
		}
	}

	// returns true if was sent to mesh
	bool meshChunk(ChunkWorldPos cwp)
	{
		ChunkSnapWithAdjacent snapWithAdjacentBlocks = chunkManager.getSnapWithAdjacent(cwp, FIRST_LAYER);
		ChunkSnapWithAdjacent snapWithAdjacentEntities = chunkManager.getSnapWithAdjacent(cwp, ENTITY_LAYER);

		if (!snapWithAdjacentBlocks.allLoaded)
		{
			version(DBG) tracef("meshChunk %s !allLoaded", cwp);
			return false;
		}

		++numMeshChunkTasks;

		if (!producesMesh(snapWithAdjacentBlocks))
		{
			version(DBG) tracef("meshChunk %s produces no mesh", cwp);

			// send remove mesh task
			with(meshWorkers.nextWorker) {
				auto header = MeshGenTaskHeader(MeshGenTaskType.unloadMesh, currentMeshGroupId, cwp);
				taskQueue.pushItem(header);
				notify();
			}

			//unloadChunkMesh(cwp);
			return true;
		}

		version(DBG) tracef("meshChunk %s", cwp);

		foreach(pos; snapWithAdjacentBlocks.positions)
		{
			chunkManager.addCurrentSnapshotUser(pos, FIRST_LAYER);
			chunkManager.addCurrentSnapshotUser(pos, ENTITY_LAYER);
		}

		ChunkLayerItem[7] blockLayers;
		ChunkLayerItem[7] entityLayers;
		foreach(i; 0..7)
		{
			blockLayers[i] = ChunkLayerItem(snapWithAdjacentBlocks.snapshots[i].get(), FIRST_LAYER);
			entityLayers[i] = ChunkLayerItem(snapWithAdjacentEntities.snapshots[i].get(), ENTITY_LAYER);
		}

		// send mesh task
		auto header = MeshGenTaskHeader(MeshGenTaskType.genMesh, currentMeshGroupId, cwp);
		with(meshWorkers.nextWorker) {
			taskQueue.startMessage();
			taskQueue.pushMessagePart(header);
			taskQueue.pushMessagePart(blockLayers);
			taskQueue.pushMessagePart(entityLayers);
			taskQueue.endMessage();
			notify();
		}

		return true;
	}

	void loadMeshData(ChunkWorldPos cwp, MeshVertex[][2] meshes)
	{
		if (!chunkManager.isChunkLoaded(cwp))
		{
			import core.memory : GC;

			version(DBG) tracef("loadMeshData %s chunk unloaded", cwp);
			GC.free(meshes[0].ptr);
			GC.free(meshes[1].ptr);
			return;
		}

		// Attach mesh
		bool hasMesh = false;
		foreach(i, meshData; meshes)
		{
			if (meshData.length == 0) {
				unloadChunkSubmesh(cwp, i);
				continue;
			}
			totalMeshDataBytes += meshData.length * MeshVertex.sizeof;
			auto mesh = cwp in chunkMeshes[i];
			if (mesh)
			{
				assert(mesh.data);
				totalMeshDataBytes -= mesh.dataBytes;

				import core.memory : GC;
				GC.free(mesh.data.ptr);

				mesh.data = meshData;
				mesh.isDataDirty = true;
			}
			else
			{
				chunkMeshes[i][cwp] = ChunkMesh(vec3(cwp.vector * CHUNK_SIZE), cwp.w, meshData);
			}

			hasMesh = true;
		}

		++totalMeshedChunks;
		if (hasMesh)
		{
			version(DBG) tracef("loadMeshData %s [%s %s]",
				cwp, cast(int)(meshes[0] !is null), cast(int)(meshes[1] !is null));
			++totalMeshes;
		}
		else
		{
			version(DBG) tracef("loadMeshData %s no mesh", cwp);

			static if (debug_wasted_meshes)
			{
				wastedMeshes[cwp] = 0;
			}
		}
	}

	void unloadChunkMesh(ChunkWorldPos cwp)
	{
		version(DBG) tracef("unloadChunkMesh %s", cwp);
		foreach(i; 0..chunkMeshes.length)
		{
			unloadChunkSubmesh(cwp, i);
		}
	}

	void unloadChunkSubmesh(ChunkWorldPos cwp, size_t index)
	{
		if (auto mesh = cwp in chunkMeshes[index])
		{
			import core.memory : GC;
			totalMeshDataBytes -= mesh.dataBytes;
			mesh.deleteBuffers();
			GC.free(mesh.data.ptr);
			chunkMeshes[index].remove(cwp);
		}
	}
}
