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
import voxelman.graphics;
import voxelman.geometry.cube;


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
	ChunkMesh[2] preloadedMeshes;
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
			auto result = MeshGenResult(taskHeader.type, taskHeader.cwp, meshes);
			preloadMesh(result);
			newChunkMeshes ~= result;
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

		foreach(ref meshResult; newChunkMeshes)
		{
			if (meshResult.type == MeshGenTaskType.genMesh)
			{
				loadMeshData(meshResult);
			}
			else // taskHeader.type == MeshGenTaskType.unloadMesh
			{
				unloadChunkMesh(meshResult.cwp);
			}
			meshResult = MeshGenResult.init;
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

	bool producesMesh(AdjChunk7Layers snapshots)
	{
		import voxelman.block.utils;

		Solidity solidity;
		bool singleSolidity = hasSingleSolidity(snapshots.central.metadata, solidity);

		if (singleSolidity)
		{
			// completely transparent chunks do not produce meshes.
			if (solidity == Solidity.transparent) {
				return false;
			}

			foreach(CubeSide side, adj; snapshots.adjacent)
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
		auto snapsPositions = AdjChunk7Positions(cwp);

		if (!chunkManager.areChunksLoaded(snapsPositions.all))
		{
			version(DBG) tracef("meshChunk %s !allLoaded", cwp);
			return false;
		}

		AdjChunk7Layers snapsBlocks;

		// get compressed layers to use metadata.
		snapsBlocks.all = chunkManager.getChunkSnapshots(snapsPositions.all, FIRST_LAYER);

		++numMeshChunkTasks;

		if (!producesMesh(snapsBlocks))
		{
			version(DBG) tracef("meshChunk %s produces no mesh", cwp);

			// send remove mesh task
			with(meshWorkers.nextWorker) {
				auto header = MeshGenTaskHeader(MeshGenTaskType.unloadMesh, currentMeshGroupId, cwp);
				taskQueue.pushItem(header);
				notify();
			}

			return true;
		}

		version(DBG) tracef("meshChunk %s", cwp);

		// get uncompressed blocks to use for meshing
		snapsBlocks.all = chunkManager.getChunkSnapshots(
			snapsPositions.all, FIRST_LAYER, Yes.Uncompress);

		AdjChunk7Layers snapsEntities;
		snapsEntities.all = chunkManager.getChunkSnapshots(
			snapsPositions.all, ENTITY_LAYER, Yes.Uncompress);

		foreach(pos; snapsPositions.all)
		{
			chunkManager.addCurrentSnapshotUser(pos, FIRST_LAYER);
			chunkManager.addCurrentSnapshotUser(pos, ENTITY_LAYER);
		}

		ChunkLayerItem[7] blockLayers;
		ChunkLayerItem[7] entityLayers;
		foreach(i; 0..7)
		{
			blockLayers[i] = ChunkLayerItem(snapsBlocks.all[i].get(), FIRST_LAYER);
			entityLayers[i] = ChunkLayerItem(snapsEntities.all[i].get(), ENTITY_LAYER);
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

	void preloadMesh(ref MeshGenResult result)
	{
		ChunkWorldPos cwp = result.cwp;
		if (!chunkManager.isChunkLoaded(cwp))
			return;

		foreach(i, meshData; result.meshes)
		{
			if (meshData.length == 0) continue;
			auto mesh = ChunkMesh(vec3(cwp.vector * CHUNK_SIZE), cwp.w);

			mesh.bind;
			mesh.uploadBuffer(meshData);
			mesh.unbind;

			result.preloadedMeshes[i] = mesh;
		}
	}

	void loadMeshData(MeshGenResult result)
	{
		ChunkWorldPos cwp = result.cwp;
		if (!chunkManager.isChunkLoaded(cwp))
		{
			version(DBG) tracef("loadMeshData %s chunk unloaded", cwp);

			result.preloadedMeshes[0].deleteBuffers();
			result.preloadedMeshes[1].deleteBuffers();

			freeChunkMesh(result.preloadedMeshes[0].data);
			freeChunkMesh(result.preloadedMeshes[1].data);

			return;
		}

		// Attach mesh
		bool hasMesh = false;
		foreach(i, chunkMesh; result.preloadedMeshes)
		{
			unloadChunkSubmesh(cwp, i);
			if (chunkMesh.empty) {
				continue;
			}

			totalMeshDataBytes += chunkMesh.dataBytes;
			chunkMeshes[i][cwp] = result.preloadedMeshes[i];
			hasMesh = true;
		}

		++totalMeshedChunks;
		if (hasMesh)
		{
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
			totalMeshDataBytes -= mesh.dataBytes;
			mesh.deleteBuffers();
			freeChunkMesh(mesh.data);
			chunkMeshes[index].remove(cwp);
		}
	}
}

void freeChunkMesh(ref MeshVertex[] data)
{
	import std.experimental.allocator;
	import std.experimental.allocator.mallocator;
	Mallocator.instance.dispose(data);
	data = null;
}
