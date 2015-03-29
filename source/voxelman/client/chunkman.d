/**
Copyright: Copyright (c) 2013-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.client.chunkman;

import std.experimental.logger;

import dlib.math.vector : vec3, ivec3;

import voxelman.block;
import voxelman.blockman;
import voxelman.storage.chunk;
import voxelman.storage.chunkstorage;
import voxelman.config;
import voxelman.client.chunkmeshman;


///
struct ChunkMan
{
	ChunkStorage chunkStorage;
	alias chunkStorage this;

	// Stats
	size_t totalLoadedChunks;

	ChunkRange visibleRegion;
	ivec3 observerPosition = ivec3(int.max, int.max, int.max);
	uint viewRadius = VIEW_RADIUS;

	BlockMan blockMan;
	ChunkMeshMan chunkMeshMan;

	void init()
	{
		blockMan.loadBlockTypes();
		chunkMeshMan.init(&this, &blockMan);
		chunkStorage.onChunkRemoved = &chunkMeshMan.onChunkRemoved;
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

	void onChunkLoaded(ivec3 chunkPos, BlockData blockData)
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

	void onChunkChanged(ivec3 chunkPos, BlockChange[] changes)
	{
		Chunk* chunk = chunkStorage.getChunk(chunkPos);

		// We can receive data for chunk that is already deleted.
		if (chunk is null || chunk.isMarkedForDeletion)
			return;

		chunkMeshMan.onChunkChanged(chunk, changes);
	}

	@property auto visibleChunks()
	{
		import std.algorithm : filter;
		return chunkStorage.chunks
			.byValue
			.filter!((c) => c.isLoaded && c.isVisible && c.hasMesh && c.mesh !is null);
	}

	ChunkRange calcChunkRange(ivec3 coord)
	{
		auto size = viewRadius*2 + 1;
		return ChunkRange(cast(ivec3)(coord - viewRadius),
			ivec3(size, size, size));
	}

	void updateObserverPosition(vec3 cameraPos)
	{
		ivec3 chunkPos = worldToChunkPos(cameraPos);

		if (chunkPos == observerPosition) return;
		observerPosition = chunkPos;

		ChunkRange newRegion = calcChunkRange(chunkPos);

		updateVisibleRegion(newRegion);
	}

	void updateVisibleRegion(ChunkRange newRegion)
	{
		auto oldRegion = visibleRegion;
		visibleRegion = newRegion;

		if (oldRegion.empty)
		{
			loadRegion(newRegion);
			return;
		}

		auto chunksToRemove = oldRegion.chunksNotIn(newRegion);

		// remove chunks
		foreach(chunkCoord; chunksToRemove)
		{
			chunkStorage.removeQueue.add(chunkStorage.getChunk(chunkCoord));
		}

		// load chunks
		// ivec3[] chunksToLoad = newRegion.chunksNotIn(oldRegion).array;
		// sort!((a, b) => a.euclidDist(observerPosition) > b.euclidDist(observerPosition))(chunksToLoad);
		foreach(chunkCoord; newRegion.chunksNotIn(oldRegion))
		{
			chunkStorage.loadChunk(chunkCoord);
		}
	}

	void loadRegion(ChunkRange region)
	{
		foreach(int x; region.coord.x..(region.coord.x + region.size.x))
		foreach(int y; region.coord.y..(region.coord.y + region.size.y))
		foreach(int z; region.coord.z..(region.coord.z + region.size.z))
		{
			chunkStorage.loadChunk(ivec3(x, y, z));
		}
	}
}
