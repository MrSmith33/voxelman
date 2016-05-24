/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.core.meshgen;

import std.experimental.logger;
import std.array : Appender;
import std.conv : to;
import core.exception : Throwable;
import core.sync.semaphore;


import voxelman.block.plugin;
import voxelman.block.utils;

import voxelman.core.config;
import voxelman.world.storage.chunk;
import voxelman.world.storage.coordinates;
import voxelman.utils.worker;


struct MeshGenResult
{
	size_t meshGroupId;
	ChunkWorldPos cwp;
	ubyte[][2] meshes;
	ChunkLayerItem[7] layers;
}

struct MeshGenTask
{
	size_t meshGroupId;
	ChunkWorldPos cwp;
	ChunkLayerItem[7] layers;
}

//version = DBG_OUT;
void meshWorkerThread(shared(Worker)* workerInfo, immutable(BlockInfo)[] blockInfos)
{
	try
	{
		while (workerInfo.isRunning)
		{
			(cast(Semaphore)workerInfo.workAvaliable).wait();

			if (!workerInfo.taskQueue.empty)
			{
				MeshGenTask task = workerInfo.taskQueue.popItem!MeshGenTask();
				ubyte[][2] meshes = chunkMeshWorker(task.layers[6], task.layers[0..6], blockInfos);
				auto result = MeshGenResult(task.meshGroupId, task.cwp, meshes, task.layers);
				workerInfo.resultQueue.pushItem!MeshGenResult(result);
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

ubyte[][2] chunkMeshWorker(ChunkLayerItem layer, ChunkLayerItem[6] adjacent, immutable(BlockInfo)[] blockInfos)
{
	Appender!(ubyte[])[3] geometry; // 2 - solid, 1 - semiTransparent

	assert(layer.type != StorageType.compressedArray, "[MESHING] Data needs to be uncompressed");
	foreach (adj; adjacent)
	{
		assert(adj.type != StorageType.compressedArray, "[MESHING] Data needs to be uncompressed");
	}

	Solidity solidity(int tx, int ty, int tz)
	{
		ubyte x = cast(ubyte)tx;
		ubyte y = cast(ubyte)ty;
		ubyte z = cast(ubyte)tz;

		if(tx == -1) // west
		{
			return blockInfos[ adjacent[Side.west].getBlockId(CHUNK_SIZE-1, y, z) ].solidity;
		}
		else if(tx == CHUNK_SIZE) // east
		{
			return blockInfos[ adjacent[Side.east].getBlockId(0, y, z) ].solidity;
		}

		if(ty == -1) // bottom
		{
			return blockInfos[ adjacent[Side.bottom].getBlockId(x, CHUNK_SIZE-1, z) ].solidity;
		}
		else if(ty == CHUNK_SIZE) // top
		{
			return blockInfos[ adjacent[Side.top].getBlockId(x, 0, z) ].solidity;
		}

		if(tz == -1) // north
		{
			return blockInfos[ adjacent[Side.north].getBlockId(x, y, CHUNK_SIZE-1) ].solidity;
		}
		else if(tz == CHUNK_SIZE) // south
		{
			return blockInfos[ adjacent[Side.south].getBlockId(x, y, 0) ].solidity;
		}

		return blockInfos[ layer.getBlockId(x, y, z) ].solidity;
	}

	if (layer.isUniform)
	{
		BlockId id = layer.getUniform!BlockId;
		Meshhandler meshHandler = blockInfos[id].meshHandler;
		ubyte[3] color = blockInfos[id].color;
		Solidity curSolidity = blockInfos[id].solidity;

		if (curSolidity != Solidity.transparent)
		{
			foreach (uint index; 0..CHUNK_SIZE_CUBE)
			{
				ubyte bx = index & CHUNK_SIZE_BITS;
				ubyte by = (index / CHUNK_SIZE_SQR) & CHUNK_SIZE_BITS;
				ubyte bz = (index / CHUNK_SIZE) & CHUNK_SIZE_BITS;

				// Bit flags of sides to render
				ubyte sides = 0;

				ubyte flag = 1;
				foreach(ubyte side; 0..6)
				{
					// Offset to adjacent block
					byte[3] offset = sideOffsets[side];

					if(curSolidity > solidity(bx+offset[0], by+offset[1], bz+offset[2]))
					{
						sides |= flag;
					}

					flag <<= 1;
				}
				meshHandler(geometry[curSolidity], color, bx, by, bz, sides);
			}
		}
	}
	else
	{
		auto blocks = layer.getArray!BlockId();
		assert(blocks.length == CHUNK_SIZE_CUBE);
		foreach (uint index, ubyte blockId; blocks)
		{
			if (blockInfos[blockId].isVisible)
			{
				ubyte bx = index & CHUNK_SIZE_BITS;
				ubyte by = (index / CHUNK_SIZE_SQR) & CHUNK_SIZE_BITS;
				ubyte bz = (index / CHUNK_SIZE) & CHUNK_SIZE_BITS;

				ubyte sides = 0; // Bit flags of sides to render

				auto curSolidity = blockInfos[blockId].solidity;
				if (curSolidity == Solidity.transparent)
					continue;

				ubyte flag = 1;
				foreach(ubyte side; 0..6)
				{
					// Offset to adjacent block
					byte[3] offset = sideOffsets[side];

					if(curSolidity > solidity(bx+offset[0], by+offset[1], bz+offset[2]))
					{
						sides |= flag;
					}

					flag <<= 1;
				}

				blockInfos[blockId].meshHandler(geometry[curSolidity], blockInfos[blockId].color, bx, by, bz, sides);
			}
		}
	}

	ubyte[][2] meshes;
	meshes[0] = geometry[2].data; // solid geometry
	meshes[1] = geometry[1].data; // semi-transparent geometry

	// Add root to data.
	// Data can be collected by GC if no-one is referencing it.
	// It is needed to pass array trough shared queue.
	// Root is removed inside ChunkMeshMan
	import core.memory : GC;
	if (meshes[0]) GC.addRoot(meshes[0].ptr); // TODO remove when moved to non-GC allocator
	if (meshes[1]) GC.addRoot(meshes[1].ptr); //

	return meshes;
}
