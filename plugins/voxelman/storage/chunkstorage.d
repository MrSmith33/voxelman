/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.storage.chunkstorage;

import dlib.math.vector : vec3, ivec3;
import voxelman.block.utils;
import voxelman.storage.chunk;
import voxelman.storage.coordinates;

struct ChunkRemoveQueue
{
	Chunk* first; // head of slist. Follow 'next' pointer in chunk
	size_t length;

	void add(Chunk* chunk)
	{
		assert(chunk);

		// already queued
		if (chunk.isMarkedForDeletion) return;

		chunk.isLoaded = false;
		chunk.next = first;
		if (first) first.prev = chunk;
		first = chunk;
		++length;
	}

	void remove(Chunk* chunk)
	{
		assert(chunk);
		assert(chunk !is null);

		if (chunk.prev)
			chunk.prev.next = chunk.next;
		else
			first = chunk.next;

		if (chunk.next)
			chunk.next.prev = chunk.prev;

		chunk.next = null;
		chunk.prev = null;
		--length;
	}

	void process(void delegate(Chunk* chunk) chunkRemoveCallback)
	{
		Chunk* chunk = first;

		while(chunk)
		{
			assert(chunk !is null);

			if (!chunk.isUsed)
			{
				auto toRemove = chunk;
				chunk = chunk.next;

				remove(toRemove);
				chunkRemoveCallback(toRemove);
			}
			else
			{
				auto c = chunk;
				chunk = chunk.next;
			}
		}
	}
}

///
struct ChunkStorage
{
	Chunk*[ChunkWorldPos] chunks;
	ChunkRemoveQueue removeQueue;
	void delegate(Chunk* chunk)[] onChunkAddedHandlers;
	void delegate(Chunk* chunk)[] onChunkRemovedHandlers;

	Chunk* getChunk(ChunkWorldPos position)
	{
		return chunks.get(position, null);
	}

	void update()
	{
		removeQueue.process(&removeChunk);
	}

	private Chunk* createEmptyChunk(ChunkWorldPos position)
	{
		return new Chunk(position);
	}

	bool loadChunk(ChunkWorldPos position)
	{
		if (auto chunk = chunks.get(position, null))
		{
			if (chunk.isMarkedForDeletion)
				removeQueue.remove(chunk);
			return chunk.isLoaded;
		}

		Chunk* chunk = createEmptyChunk(position);
		addChunk(chunk);

		return false;
	}

	// Add already created chunk to storage
	// Sets up all adjacent
	private void addChunk(Chunk* emptyChunk)
	{
		assert(emptyChunk);
		chunks[emptyChunk.position] = emptyChunk;
		ChunkWorldPos position = emptyChunk.position;

		void attachAdjacent(ubyte side)()
		{
			byte[3] offset = sideOffsets[side];
			ChunkWorldPos otherPosition = ivec3(cast(int)(position.x + offset[0]),
												cast(int)(position.y + offset[1]),
												cast(int)(position.z + offset[2]));
			Chunk* other = getChunk(otherPosition);

			if (other !is null)
				other.adjacent[oppSide[side]] = emptyChunk;
			emptyChunk.adjacent[side] = other;
		}

		// Attach all adjacent
		attachAdjacent!(0)();
		attachAdjacent!(1)();
		attachAdjacent!(2)();
		attachAdjacent!(3)();
		attachAdjacent!(4)();
		attachAdjacent!(5)();

		foreach(handler; onChunkAddedHandlers)
			handler(emptyChunk);
	}

	void removeChunk(Chunk* chunk)
	{
		assert(chunk);
		assert(!chunk.isUsed);

		void detachAdjacent(ubyte side)()
		{
			if (chunk.adjacent[side] !is null)
			{
				chunk.adjacent[side].adjacent[oppSide[side]] = null;
			}
			chunk.adjacent[side] = null;
		}

		// Detach all adjacent
		detachAdjacent!(0)();
		detachAdjacent!(1)();
		detachAdjacent!(2)();
		detachAdjacent!(3)();
		detachAdjacent!(4)();
		detachAdjacent!(5)();

		chunks.remove(chunk.position);
		foreach(handler; onChunkRemovedHandlers)
			handler(chunk);

		if (chunk.mesh)
			chunk.mesh.free();
		delete chunk.mesh;
		delete chunk;
	}
}
