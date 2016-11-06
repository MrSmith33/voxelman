/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.client.chunkmeshman;

import voxelman.log;
import std.typecons : Nullable;

import voxelman.geometry.box;
import voxelman.math;
import voxelman.block.utils;
import voxelman.blockentity.utils;
import voxelman.core.chunkmesh;
import voxelman.core.config;
import voxelman.core.meshgen;
import voxelman.world.storage;
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
	Box delegate(DimensionId) getDimensionBorders;

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
		foreach(cwp; modifiedChunks)
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
			uint[27] blockTimestamps = w.resultQueue.popItem!(uint[27])();
			uint[27] entityTimestamps = w.resultQueue.popItem!(uint[27])();

			// Remove users
			auto positions = AdjChunkPositions27(taskHeader.cwp);
			foreach(i, pos; positions.all)
			{
				if (blockTimestamps[i] == uint.max) continue; // out-of-border chunk
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

	bool producesMesh(
		const ref Nullable!ChunkLayerSnap[6] adjacent,
		const ref ChunkLayerSnap central)
	{
		import voxelman.block.utils;

		Solidity solidity;
		bool singleSolidity = hasSingleSolidity(central.metadata, solidity);

		if (singleSolidity)
		{
			// completely transparent chunks do not produce meshes.
			if (solidity == Solidity.transparent) {
				return false;
			}

			foreach(CubeSide side, adj; adjacent)
			{
				if (!adj.isNull())
				{
					Solidity adjSideSolidity = chunkSideSolidity(adj.metadata, oppSide[side]);
					if (solidity.isMoreSolidThan(adjSideSolidity)) return true;
				}
				// otherwise it is unknown blocks, which are solid
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
		Box dimBorders = getDimensionBorders(cwp.w);
		auto snapsPositions = AdjChunkPositions27(cwp);

		foreach(pos; snapsPositions.all)
		{
			if (!chunkManager.isChunkLoaded(pos))
			{
				if (dimBorders.contains(pos.ivector3))
				{
					// chunk in dim borders is not loaded
					return false;
				}
			}
		}

		assert(dimBorders.contains(snapsPositions.central.ivector3));

		AdjChunkLayers27 snapsBlocks;

		// get compressed layers first to look at metadata.
		snapsBlocks.adjacent6 = chunkManager.getChunkSnapshots(snapsPositions.adjacent6, FIRST_LAYER);
		snapsBlocks.central = chunkManager.getChunkSnapshot(snapsPositions.central, FIRST_LAYER);

		++numMeshChunkTasks;

		if (!producesMesh(snapsBlocks.adjacent6, snapsBlocks.central))
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

		AdjChunkLayers27 snapsEntities;
		snapsEntities.all = chunkManager.getChunkSnapshots(
			snapsPositions.all, ENTITY_LAYER, Yes.Uncompress);

		ChunkLayerItem[27] blockLayers;
		ChunkLayerItem[27] entityLayers;
		foreach(i; 0..27)
		{
			if (!dimBorders.contains(snapsPositions.all[i].ivector3)) // out-of-border chunk
			{
				blockLayers[i].timestamp = uint.max; // mark as not loaded, to not remove users later
				blockLayers[i].metadata = solidity_metadatas[Solidity.solid];
			}
			else
			{
				blockLayers[i] = ChunkLayerItem(snapsBlocks.all[i].get(), FIRST_LAYER);
				entityLayers[i] = ChunkLayerItem(snapsEntities.all[i].get(), ENTITY_LAYER);
			}
		}

		foreach(pos; snapsPositions.all)
		{
			if (!dimBorders.contains(pos.ivector3)) continue; // out-of-border chunk
			chunkManager.addCurrentSnapshotUser(pos, FIRST_LAYER);
			chunkManager.addCurrentSnapshotUser(pos, ENTITY_LAYER);
		}

		// debug
		foreach (i, layer; blockLayers) {
			import std.string : format;
			assert(layer.type != StorageType.compressedArray, "[MESHING] Data needs to be uncompressed 1");
			if (!layer.isUniform) {
				auto length = layer.getArray!ubyte.length;
				if (length != BLOCKS_DATA_LENGTH) infof("Wrong length of %s: %s", snapsPositions.all[i], length);
				assert(length == BLOCKS_DATA_LENGTH, format("Wrong length of %s: %s", snapsPositions.all[i], length));
			}
		}
		foreach (i, layer; entityLayers)
			assert(layer.type != StorageType.compressedArray, "[MESHING] Data needs to be uncompressed 2");

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

			mesh.uploadBuffer(meshData);

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
			chunkMeshes[index].remove(cwp);
		}
	}
}
