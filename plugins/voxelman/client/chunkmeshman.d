/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.client.chunkmeshman;

import std.experimental.logger;

import voxelman.block.utils;
import voxelman.core.chunkmesh;
import voxelman.core.config;
import voxelman.core.meshgen;
import voxelman.world.storage.chunk;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.chunkmanager;
import voxelman.utils.worker;
import voxelman.utils.hashset;
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

	ChunkManager chunkManager;
	immutable(BlockInfo)[] blocks;

	void init(ChunkManager _chunkManager, immutable(BlockInfo)[] _blocks, uint numMeshWorkers)
	{
		chunkManager = _chunkManager;
		blocks = _blocks;
		meshWorkers.startWorkers(numMeshWorkers, &meshWorkerThread, blocks);
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
		//infof("meshingPasses ~= %s", meshingPasses[$-1]);
		++currentMeshGroupId;
		//infof("currentMeshGroupId %s", currentMeshGroupId);
	}

	void update()
	{
		if (meshingPasses.length == 0) return;

		foreach(ref w; meshWorkers.workers)
		{
			while(!w.resultQueue.empty)
			{
				auto result = w.resultQueue.peekItem!MeshGenResult();

				// Process only current meshing pass. Leave next passes for later.
				if (result.meshGroupId != meshingPasses[0].meshGroupId)
				{
					//infof("meshGroup %s != %s", result.meshGroupId, meshingPasses[0].meshGroupId);
					break;
				}

				++meshingPasses[0].chunksMeshed;

				w.resultQueue.dropItem!MeshGenResult();

				--numMeshChunkTasks;

				newChunkMeshes ~= result;

				// Remove root, added on chunk load and gen.
				// Data can be collected by GC if no-one is referencing it.
				import core.memory : GC;
				if (result.meshes[0].ptr) GC.removeRoot(result.meshes[0].ptr); // TODO remove when moved to non-GC allocator
				if (result.meshes[1].ptr) GC.removeRoot(result.meshes[1].ptr); //
			}
		}

		commitMeshes();
	}

	void commitMeshes()
	{
		import std.algorithm : remove, SwapStrategy;
		if (meshingPasses[0].chunksMeshed != meshingPasses[0].chunksToMesh) return;

		foreach(meshResult; newChunkMeshes)
		{
			loadMeshData(meshResult.cwp, meshResult.meshes, meshResult.layers);
		}
		newChunkMeshes.length = 0;
		//newChunkMeshes.assumeSafeAppend();
		if (meshingPasses[0].onDone)
			meshingPasses[0].onDone(meshingPasses[0].chunksToMesh);
		meshingPasses = remove!(SwapStrategy.stable)(meshingPasses, 0);
		//meshingPasses.assumeSafeAppend();
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

	bool surroundedBySolidChunks(ChunkSnapWithAdjacent snapWithAdjacent)
	{
		/+
		import voxelman.block.utils;
		assert(snapWithAdjacent.allLoaded);

		Solidity thisMinSolidity = chunkMinSolidity(snapWithAdjacent.centralSnapshot.metadata);

		if (thisMinSolidity == Solidity.transparent) return true;

		foreach(Side side, adj; snapWithAdjacent.adjacentSnapshots)
		{
			/*
			if (adj.isUniform)
			{
				Solidity solidity = chunkSideSolidity(adj.metadata, oppSide[side]);
				if (thisMinSolidity.isMoreSolidThan(solidity)) return false;
			}
			else
			{
				bool solidSide = isChunkSideSolid(adj.metadata, oppSide[side]);
				if (!solidSide) return false;
			}
			*/
			Solidity adjSolidity = chunkSideSolidity(adj.metadata, oppSide[side]);
			Solidity thisSideSolidity = chunkSideSolidity(snapWithAdjacent.centralSnapshot.metadata, side);
			if (thisSideSolidity.isMoreSolidThan(adjSolidity)) return false;
		}

		return true;+/

		import voxelman.block.utils;
		Solidity thisMinSolidity = chunkMinSolidity(snapWithAdjacent.centralSnapshot.metadata);

		if (snapWithAdjacent.centralSnapshot.isUniform) {
			if (thisMinSolidity == Solidity.transparent) {
				return true;
			}
		}

		foreach(Side side, adj; snapWithAdjacent.adjacentSnapshots)
		{
			if (snapWithAdjacent.centralSnapshot.isUniform) {
				Solidity solidity = chunkSideSolidity(adj.metadata, oppSide[side]);
				if (thisMinSolidity.isMoreSolidThan(solidity)) return false;
			} else {
				bool solidSide = isChunkSideSolid(adj.metadata, oppSide[side]);
				if (!solidSide) return false;
			}
		}
		return true;
	}

	// returns true if was sent to mesh
	bool meshChunk(ChunkWorldPos cwp)
	{
		ChunkSnapWithAdjacent snapWithAdjacent = chunkManager.getSnapWithAdjacentAddUsers(cwp, FIRST_LAYER);

		if (!snapWithAdjacent.allLoaded)
		{
			version(DBG) tracef("meshChunk %s !allLoaded", cwp);
			return false;
		}

		if (surroundedBySolidChunks(snapWithAdjacent))
		{
			version(DBG) tracef("meshChunk %s surrounded by solid chunks", cwp);
			return false;
		}

		version(DBG) tracef("meshChunk %s", cwp);

		foreach(pos; snapWithAdjacent.positions)
		{
			chunkManager.addCurrentSnapshotUser(pos, FIRST_LAYER);
		}

		++numMeshChunkTasks;

		ChunkLayerItem[7] layers;
		foreach(i; 0..7)
		{
			layers[i] = ChunkLayerItem(snapWithAdjacent.snapshots[i].get(), FIRST_LAYER);
		}

		auto task = MeshGenTask(currentMeshGroupId, cwp, layers);
		//infof("push %s", task);
		with(meshWorkers.nextWorker) {
			taskQueue.pushItem(task);
			notify();
		}

		return true;
	}

	void loadMeshData(ChunkWorldPos cwp, ubyte[][2] meshes, ChunkLayerItem[7] layers)
	{
		ChunkWorldPos[7] positions;
		positions[0..6] = adjacentPositions(cwp);
		positions[6] = cwp;
		foreach(i, pos; positions)
		{
			chunkManager.removeSnapshotUser(pos, layers[i].timestamp, FIRST_LAYER);
		}

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

			auto mesh = cwp in chunkMeshes[i];
			if (mesh)
			{
				assert(mesh.data);
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
			unloadChunkMesh(cwp);

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
			mesh.deleteBuffers();
			GC.free(mesh.data.ptr);
			chunkMeshes[index].remove(cwp);
		}
	}
}
