/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.mesh.chunkmeshman;

import voxelman.log;
import std.datetime : Duration;
import std.typecons : Nullable;
import voxelman.platform.isharedcontext;

import voxelman.math;
import voxelman.world.block;
import voxelman.world.blockentity;
import voxelman.world.mesh.chunkmesh;
import voxelman.core.config;
import voxelman.world.mesh.meshgen;
import voxelman.world.storage;
import voxelman.thread.worker;
import voxelman.container.hash.set;
import voxelman.graphics;
import voxelman.geometry;


alias MeshingPassDoneHandler = void delegate(size_t chunksRemeshed, Duration totalDuration);
struct MeshingPass
{
	size_t chunksToMesh;
	size_t meshGroupId;
	MeshingPassDoneHandler onDone;
	size_t chunksMeshed;
	Duration totalDuration;
}

enum debug_wasted_meshes = true;
enum WAIT_FOR_EMPTY_QUEUES = false;

//version = DBG;

struct MeshGenResult
{
	MeshGenTaskType type;
	ChunkWorldPos cwp;
	ChunkMesh[2] meshes;
}

struct UploadLimiter
{
	bool limitPreloadSpeed = false;
	size_t maxPreloadedMeshesPerFrame = 30;
	size_t maxPreloadedVertexesPerFrame = 100_000;

	size_t thisFramePreloadedMeshes;
	size_t thisFramePreloadedVertexes;

	bool frameUploadLimitExceeded()
	{
		//return thisFramePreloadedMeshes >= maxPreloadedMeshesPerFrame;
		return limitPreloadSpeed && thisFramePreloadedVertexes >= maxPreloadedVertexesPerFrame;
	}

	void onMeshPreloaded(size_t numVertexes)
	{
		++thisFramePreloadedMeshes;
		thisFramePreloadedVertexes += numVertexes;
	}

	void resetUploadLimits()
	{
		thisFramePreloadedMeshes = 0;
		thisFramePreloadedVertexes = 0;
	}
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

	UploadLimiter uploadLimiter;

	ChunkManager chunkManager;
	BlockInfoTable blocks;
	BlockEntityInfoTable beInfos;
	Box delegate(DimensionId) getDimensionBorders;

	void init(ChunkManager _chunkManager, BlockInfoTable _blocks, BlockEntityInfoTable _beInfos, uint numMeshWorkers)
	{
		chunkManager = _chunkManager;
		blocks = _blocks;
		beInfos = _beInfos;

		meshWorkers.startWorkers(numMeshWorkers, &meshWorkerThread, SeparatedBlockInfoTable(blocks), beInfos);
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

	// Returns number of chunks sent to be meshed
	size_t remeshChangedChunks(HashSet!ChunkWorldPos modifiedChunks,
		MeshingPassDoneHandler onDone = null)
	{
		if (modifiedChunks.length == 0) return 0;

		size_t numMeshed;
		foreach(cwp; modifiedChunks)
		{
			if (meshChunk(cwp))
				++numMeshed;
		}

		if (numMeshed == 0) return 0;

		meshingPasses ~= MeshingPass(numMeshed, currentMeshGroupId, onDone);
		++currentMeshGroupId;

		return numMeshed;
	}

	void update()
	{
		if (meshingPasses.length == 0) return;

		uploadLimiter.resetUploadLimits();

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
			uint[27] metadataTimestamps = w.resultQueue.popItem!(uint[27])();
			meshingPasses[0].totalDuration += w.resultQueue.popItem!Duration();

			// Remove users
			auto positions = AdjChunkPositions27(taskHeader.cwp);
			foreach(i, pos; positions.all)
			{
				chunkManager.removeSnapshotUser(pos, blockTimestamps[i], BLOCK_LAYER);
				chunkManager.removeSnapshotUser(pos, entityTimestamps[i], ENTITY_LAYER);
				chunkManager.removeSnapshotUser(pos, metadataTimestamps[i], METADATA_LAYER);
			}

			// save result for later. All new meshes are loaded at once to prevent holes in geometry.
			auto result = MeshGenResult(taskHeader.type, taskHeader.cwp);
			preloadMesh(result, meshes);
			newChunkMeshes ~= result;
		}
		else // taskHeader.type == MeshGenTaskType.unloadMesh
		{
			// even mesh deletions are saved in a queue.
			newChunkMeshes ~= MeshGenResult(taskHeader.type, taskHeader.cwp);
		}

		if (uploadLimiter.frameUploadLimitExceeded)
			return true;

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
			meshingPasses[0].onDone(meshingPasses[0].chunksToMesh, meshingPasses[0].totalDuration);
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
		import voxelman.world.block;

		Solidity solidity;
		bool singleSolidity = hasSingleSolidity(central.metadata, solidity);

		if (singleSolidity)
		{
			// completely transparent chunks do not produce meshes.
			if (solidity == Solidity.transparent) {
				return false;
			} else {
				if (central.isUniform)
				{
					// uniform unknown chunks do not produce mesh.
					if (central.getUniform!BlockId == 0)
						return false;
				}
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
		snapsBlocks.central = chunkManager.getChunkSnapshot(snapsPositions.central, BLOCK_LAYER);
		if (snapsBlocks.central.isNull())
			return false;
		snapsBlocks.adjacent6 = chunkManager.getChunkSnapshots(snapsPositions.adjacent6, BLOCK_LAYER);

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
			snapsPositions.all, BLOCK_LAYER, Yes.Uncompress);

		AdjChunkLayers27 snapsEntities;
		snapsEntities.all = chunkManager.getChunkSnapshots(
			snapsPositions.all, ENTITY_LAYER, Yes.Uncompress);

		AdjChunkLayers27 snapsMetadatas;
		snapsMetadatas.all = chunkManager.getChunkSnapshots(
			snapsPositions.all, METADATA_LAYER, Yes.Uncompress);

		ChunkLayerItem[27] blockLayers;
		ChunkLayerItem[27] entityLayers;
		ChunkLayerItem[27] metadataLayers;
		foreach(i; 0..27)
		{
			if (!dimBorders.contains(snapsPositions.all[i].ivector3)) // out-of-border chunk
			{
				blockLayers[i].metadata = solidity_metadatas[Solidity.solid];
			}
			else
			{
				blockLayers[i] = ChunkLayerItem(snapsBlocks.all[i].get(), BLOCK_LAYER);
				entityLayers[i] = ChunkLayerItem(snapsEntities.all[i].get(), ENTITY_LAYER);
				metadataLayers[i] = ChunkLayerItem(snapsMetadatas.all[i].get(), METADATA_LAYER);
			}
		}

		foreach(i, pos; snapsPositions.all)
		{
			blockLayers[i].timestamp = chunkManager.addCurrentSnapshotUser(pos, BLOCK_LAYER);
			entityLayers[i].timestamp = chunkManager.addCurrentSnapshotUser(pos, ENTITY_LAYER);
			metadataLayers[i].timestamp = chunkManager.addCurrentSnapshotUser(pos, METADATA_LAYER);
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
		foreach (layer; entityLayers)
			assert(layer.type != StorageType.compressedArray, "[MESHING] Data needs to be uncompressed 2");
		foreach (layer; metadataLayers)
			assert(layer.type != StorageType.compressedArray, "[MESHING] Data needs to be uncompressed 3");

		// send mesh task
		auto header = MeshGenTaskHeader(MeshGenTaskType.genMesh, currentMeshGroupId, cwp);
		with(meshWorkers.nextWorker) {
			taskQueue.startMessage();
			taskQueue.pushMessagePart(header);
			taskQueue.pushMessagePart(blockLayers);
			taskQueue.pushMessagePart(entityLayers);
			taskQueue.pushMessagePart(metadataLayers);
			taskQueue.endMessage();
			notify();
		}

		return true;
	}

	void preloadMesh(ref MeshGenResult result, MeshVertex[][2] meshes)
	{
		ChunkWorldPos cwp = result.cwp;
		if (!chunkManager.isChunkLoaded(cwp))
			return;

		foreach(i, meshData; meshes)
		{
			if (meshData.length == 0) continue;
			auto mesh = ChunkMesh(vec3(cwp.vector * CHUNK_SIZE));
			mesh.uploadMeshData(meshData);
			uploadLimiter.onMeshPreloaded(meshData.length);
			freeChunkMeshData(meshData);
			result.meshes[i] = mesh;
		}
	}

	void loadMeshData(MeshGenResult result)
	{
		ChunkWorldPos cwp = result.cwp;
		if (!chunkManager.isChunkLoaded(cwp))
		{
			version(DBG) tracef("loadMeshData %s chunk unloaded", cwp);

			result.meshes[0].del();
			result.meshes[1].del();

			return;
		}

		// Attach mesh
		bool hasMesh = false;
		foreach(i, mesh; result.meshes)
		{
			unloadChunkSubmesh(cwp, i);
			if (mesh.empty) {
				mesh.del;
				continue;
			}

			totalMeshDataBytes += mesh.uploadedBytes;
			chunkMeshes[i][cwp] = mesh;
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
			totalMeshDataBytes -= mesh.uploadedBytes;
			mesh.del();
			chunkMeshes[index].remove(cwp);
		}
	}
}
