/**
Copyright: Copyright (c) 2013-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.mesh.meshgen;

import voxelman.log;
import std.datetime;
import std.conv : to;
import core.exception : Throwable;
import voxelman.platform.isharedcontext;

import voxelman.container.buffer;
import voxelman.math;
import voxelman.geometry;

import voxelman.world.block;
import voxelman.world.blockentity;

import voxelman.world.block;
import voxelman.world.mesh.chunkmesh;
import voxelman.world.mesh.extendedchunk;
import voxelman.core.config;
import voxelman.thread.worker;
import voxelman.world.storage;


enum MeshGenTaskType : ubyte
{
	genMesh,
	unloadMesh
}

struct MeshGenTaskHeader
{
	MeshGenTaskType type;
	size_t meshGroupId;
	ChunkWorldPos cwp;
}

//version = DBG_OUT;
void meshWorkerThread(shared(Worker)* workerInfo, SeparatedBlockInfoTable blockInfos, BlockEntityInfoTable beInfos)
{
	// reusable buffers
	Buffer!MeshVertex[3] geometry; // 2 - solid, 1 - semiTransparent

	try
	{
		while (workerInfo.needsToRun)
		{
			workerInfo.waitForNotify();

			// receive
			//   MeshGenTaskHeader taskHeader;
			//   ChunkLayerItem[7] blockLayers;
			//   ChunkLayerItem[7] entityLayers;
			// or
			//   MeshGenTaskHeader taskHeader;
			//
			// send
			//   MeshGenTaskHeader taskHeader;
			//   MeshVertex[][2] meshes;
			//   uint[7] blockTimestamps;
			//   uint[7] entityTimestamps;
			// or
			//   MeshGenTaskHeader taskHeader;
			if (!workerInfo.taskQueue.empty)
			{
				auto taskHeader = workerInfo.taskQueue.popItem!MeshGenTaskHeader();

				if (taskHeader.type == MeshGenTaskType.genMesh)
				{
					auto taskStartTime = MonoTime.currTime;

					// get mesh task.
					auto blockLayers = workerInfo.taskQueue.popItem!(ChunkLayerItem[27]);
					auto entityLayers = workerInfo.taskQueue.popItem!(ChunkLayerItem[27]);
					auto metadataLayers = workerInfo.taskQueue.popItem!(ChunkLayerItem[27]);

					chunkMeshWorker(
						blockLayers, entityLayers, metadataLayers,
						blockInfos, beInfos, geometry);

					import std.experimental.allocator;
					import std.experimental.allocator.mallocator;

					MeshVertex[][2] meshes;
					meshes[0] = makeArray!MeshVertex(Mallocator.instance, geometry[2].data); // solid geometry
					meshes[1] = makeArray!MeshVertex(Mallocator.instance, geometry[1].data); // semi-transparent geometry
					geometry[1].clear();
					geometry[2].clear();

					uint[27] blockTimestamps;
					uint[27] entityTimestamps;
					uint[27] metadataTimestamps;
					foreach(i; 0..27) blockTimestamps[i] = blockLayers[i].timestamp;
					foreach(i; 0..27) entityTimestamps[i] = entityLayers[i].timestamp;
					foreach(i; 0..27) metadataTimestamps[i] = metadataLayers[i].timestamp;

					auto duration = MonoTime.currTime - taskStartTime;

					workerInfo.resultQueue.startMessage();
					workerInfo.resultQueue.pushMessagePart(taskHeader);
					workerInfo.resultQueue.pushMessagePart(meshes);
					workerInfo.resultQueue.pushMessagePart(blockTimestamps);
					workerInfo.resultQueue.pushMessagePart(entityTimestamps);
					workerInfo.resultQueue.pushMessagePart(metadataTimestamps);
					workerInfo.resultQueue.pushMessagePart(duration);
					workerInfo.resultQueue.endMessage();
				}
				else
				{
					// remove mesh task. Resend it to main thread.
					workerInfo.resultQueue.pushItem(taskHeader);
				}
			}
		}
	}
	catch(Throwable t)
	{
		infof("%s from mesh worker", t.to!string);
		throw t;
	}
	version(DBG_OUT)infof("Mesh worker stopped");
}

import voxelman.world.mesh.meshgenerator;

void chunkMeshWorker(
	ChunkLayerItem[27] blockLayers,
	ChunkLayerItem[27] entityLayers,
	ChunkLayerItem[27] metadataLayers,
	SeparatedBlockInfoTable blockInfos,
	BlockEntityInfoTable beInfos,
	ref Buffer!MeshVertex[3] geometry)
{
	foreach (layer; blockLayers) {
		assert(layer.type != StorageType.compressedArray, "[MESHING] Data needs to be uncompressed 1");
		if (!layer.isUniform)
			assert(layer.getArray!ubyte.length == BLOCKS_DATA_LENGTH);
	}
	foreach (layer; entityLayers)
		assert(layer.type != StorageType.compressedArray, "[MESHING] Data needs to be uncompressed 2");

	BlockEntityMap[27] maps;
	foreach (i, layer; entityLayers) maps[i] = getHashMapFromLayer(layer);

	ExtendedChunk chunk;
	chunk.create(blockLayers);
	genGeometry(chunk, entityLayers, metadataLayers, beInfos, blockInfos, geometry);
}
