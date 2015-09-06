/**
Copyright: Copyright (c) 2013-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.client.chunkman;

import std.experimental.logger;
import std.datetime : StopWatch, Duration;

import dlib.math.vector : vec3, ivec3;

import voxelman.block;
import voxelman.blockman;
import voxelman.client.chunkmeshman;
import voxelman.config;
import voxelman.storage.chunk;
import voxelman.storage.chunkstorage;
import voxelman.storage.coordinates;
import voxelman.storage.utils;

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

	BlockMan blockMan;
	ChunkMeshMan chunkMeshMan;

	void init()
	{
		blockMan.loadBlockTypes();
		chunkMeshMan.init(&this, &blockMan);
		chunkStorage.onChunkRemovedHandlers ~= &chunkMeshMan.onChunkRemoved;
	}

	void stop()
	{
		info("unloading chunks");

		foreach(chunk; chunkStorage.chunks.byValue)
			chunkStorage.removeQueue.add(chunk);

		while(chunkStorage.chunks.length > 0)
		{
			chunkStorage.update();
		}

		chunkMeshMan.stop();
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

	Volume calcVolume(ChunkWorldPos position)
	{
		auto size = viewRadius*2 + 1;
		return Volume(cast(ivec3)(position.vector - viewRadius),
			ivec3(size, size, size));
	}

	void updateObserverPosition(vec3 cameraPos)
	{
		ChunkWorldPos chunkPos = BlockWorldPos(cameraPos);
		observerPosition = chunkPos;

		Volume newVolume = calcVolume(chunkPos);
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
