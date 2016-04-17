/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.chunkman;

import std.experimental.logger;
import std.datetime : StopWatch, Duration;

import dlib.math.vector : vec3, ivec3;

import voxelman.client.chunkmeshman;
import voxelman.block.plugin;
import voxelman.block.utils;
import voxelman.core.config;
import voxelman.world.storage.chunk;
import voxelman.world.storage.chunkstorage;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.utils;
import voxelman.world.storage.volume;

///
struct ChunkMan
{
	ChunkStorage chunkStorage;
	alias chunkStorage this;

	// Stats
	size_t totalLoadedChunks;

	Volume visibleVolume;
	ChunkWorldPos observerPosition;
	int viewRadius = DEFAULT_VIEW_RADIUS;

	ChunkMeshMan chunkMeshMan;

	void init(uint numWorkers, immutable(BlockInfo)[] blocks)
	{
		chunkMeshMan.init(&this, blocks, numWorkers);
		chunkStorage.onChunkRemovedHandlers ~= &chunkMeshMan.onChunkRemoved;
	}

	void stop()
	{
		info("unloading chunks");

		foreach(chunk; chunkStorage.chunks.byValue)
			chunkStorage.removeQueue.add(chunk);

		while(chunkMeshMan.numMeshChunkTasks > 0)
		{
			chunkMeshMan.update();
		}
		chunkMeshMan.stop();
		while(chunkStorage.chunks.length > 0)
		{
			chunkStorage.update();
		}
	}

	void update()
	{
		chunkMeshMan.update();
		chunkStorage.update();
	}

	void onChunkLoaded(ChunkWorldPos chunkPos, BlockData blockData)
	{
		Chunk* chunk = chunkStorage.getChunk(chunkPos);

		// We can receive data for chunk that is already deleted.
		if (chunk is null || chunk.isMarkedForDeletion)
		{
			blockData.deleteBlocks();
			return;
		}

		chunkMeshMan.onChunkLoaded(chunk, blockData);
	}

	void onChunkChanged(Chunk* chunk, BlockChange[] changes)
	{
		chunkMeshMan.onChunkChanged(chunk, changes);
	}

	void updateObserverPosition(vec3 cameraPos)
	{
		ChunkWorldPos chunkPos = BlockWorldPos(cameraPos);
		observerPosition = chunkPos;

		Volume newVolume = calcVolume(chunkPos, viewRadius);
		if (newVolume == visibleVolume) return;

		updateVisibleVolume(newVolume);
	}

	void updateVisibleVolume(Volume newVolume)
	{
		auto oldVolume = visibleVolume;
		visibleVolume = newVolume;

		if (oldVolume.empty)
		{
			loadVolume(newVolume);
			return;
		}

		auto trisectResult = trisect(oldVolume, newVolume);
		auto chunksToRemove = trisectResult.aPositions;
		auto chunksToLoad = trisectResult.bPositions;

		// remove chunks
		foreach(chunkPos; chunksToRemove)
		{
			chunkStorage
				.removeQueue
				.add(chunkStorage.getChunk(ChunkWorldPos(chunkPos)));
		}

		// load chunks
		foreach(chunkPos; chunksToLoad)
		{
			chunkStorage.loadChunk(ChunkWorldPos(chunkPos));
		}
	}

	void loadVolume(Volume volume)
	{
		import std.algorithm : each;
		volume.positions.each!(pos => chunkStorage.loadChunk(ChunkWorldPos(pos)));
	}
}
