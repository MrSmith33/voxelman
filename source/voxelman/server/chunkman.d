/**
Copyright: Copyright (c) 2013-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.server.chunkman;

import std.experimental.logger;

import dlib.math.vector : vec3, ivec3;

import netlib;

import voxelman.block;
import voxelman.config;
import voxelman.packets;
import voxelman.server.clientinfo;
import voxelman.server.serverplugin;
import voxelman.storage.chunk;
import voxelman.storage.chunkprovider;
import voxelman.storage.chunkstorage;
import voxelman.storage.coordinates;
import voxelman.storage.utils;


struct ChunkObserverList
{
	ClientId[] observers;

	ClientId[] opIndex()
	{
		return observers;
	}

	bool empty() @property
	{
		return observers.length == 0;
	}

	void add(ClientId clientId)
	{
		observers ~= clientId;
	}

	void remove(ClientId clientId)
	{
		import std.algorithm : remove, SwapStrategy;
		observers = remove!((a) => a == clientId, SwapStrategy.unstable)(observers);
	}
}


///
struct ChunkMan
{
	@disable this();
	this(ServerConnection connection, ChunkStorage* chunkStorage)
	{
		assert(connection);
		this.connection = connection;
		assert(chunkStorage);
		this.chunkStorage = chunkStorage;
	}

	ChunkStorage* chunkStorage;

	ServerConnection connection;
	ChunkObserverList[ChunkWorldPos] chunkObservers;
	BlockChange[][ChunkWorldPos] chunkChanges;

	size_t totalObservedChunks;

	void removeRegionObserver(ClientId clientId)
	{
		auto volume = connection.clientStorage[clientId].visibleVolume;
		foreach(chunkPosition; volume.positions)
		{
			removeChunkObserver(ChunkWorldPos(chunkPosition), clientId);
		}
	}

	void updateObserverPosition(ClientId clientId)
	{
		ClientInfo* clientInfo = connection.clientStorage[clientId];
		assert(clientInfo, "clientStorage[clientId] is null");
		Volume oldVolume = clientInfo.visibleVolume;

		ChunkWorldPos chunkPos = BlockWorldPos(clientInfo.pos);
		Volume newVolume = calcVolume(chunkPos.vector, clientInfo.viewRadius);
		if (oldVolume == newVolume) return;

		onClientVisibleVolumeChanged(oldVolume, newVolume, clientId);
		connection.clientStorage[clientId].visibleVolume = newVolume;
	}

	void onClientVisibleVolumeChanged(Volume oldVolume, Volume newVolume, ClientId clientId)
	{
		if (oldVolume.empty)
		{
			//trace("observe volume");
			observeChunks(newVolume.positions, clientId);
			return;
		}

		auto trisectResult = trisect(oldVolume, newVolume);
		auto chunksToRemove = trisectResult.aPositions;
		auto chunksToLoad = trisectResult.bPositions;

		// remove chunks
		foreach(chunkPosition; chunksToRemove)
		{
			removeChunkObserver(ChunkWorldPos(chunkPosition), clientId);
		}

		// load chunks
		observeChunks(chunksToLoad, clientId);
	}

	void onChunkAdded(Chunk* chunk)
	{
		chunkObservers[chunk.position] = ChunkObserverList();
	}

	void onChunkLoaded(Chunk* chunk)
	{
		// Send data to observers
		sendChunkToObservers(chunk.position);
	}

	void onChunkRemoved(Chunk* chunk)
	{
		assert(chunkObservers.get(chunk.position, ChunkObserverList.init).empty);
		chunkObservers.remove(chunk.position);
	}

	// world change observer method
	void onChunkModified(Chunk* chunk, BlockChange[] blockChanges)
	{
		chunkChanges[chunk.position] = chunkChanges.get(chunk.position, null) ~ blockChanges;
	}

	void observeChunks(R)(R chunkPositions, ClientId clientId)
	{
		import std.range : array;
		import std.algorithm : sort;

		ClientInfo* clientInfo = connection.clientStorage[clientId];
		ivec3 observerPos = ivec3(clientInfo.pos);

		ivec3[] chunksToObserve = chunkPositions.array;
		sort!((a, b) => a.euclidDistSqr(observerPos) < b.euclidDistSqr(observerPos))(chunksToObserve);

		foreach(chunkPosition; chunksToObserve)
		{
			addChunkObserver(ChunkWorldPos(chunkPosition), clientId);
		}
	}

	void addChunkObserver(ChunkWorldPos position, ClientId clientId)
	{
		if (!isChunkInWorldBounds(position)) return;

		bool alreadyLoaded = chunkStorage.loadChunk(position);

		if (chunkObservers[position].empty)
		{
			++totalObservedChunks;
		}

		chunkObservers[position].add(clientId);

		if (alreadyLoaded)
		{
			sendChunkTo(position, clientId);
		}
	}

	void removeChunkObserver(ChunkWorldPos position, ClientId clientId)
	{
		if (!isChunkInWorldBounds(position)) return;

		chunkObservers[position].remove(clientId);

		if (chunkObservers[position].empty)
		{
			chunkStorage.removeQueue.add(chunkStorage.getChunk(position));
			--totalObservedChunks;
		}
	}

	void sendChunkToObservers(ChunkWorldPos position)
	{
		//tracef("send chunk to all %s %s", position, chunkStorage.getChunk(position).snapshot.blockData.blocks.length);
		sendToChunkObservers(position,
			ChunkDataPacket(position.vector, chunkStorage.getChunk(position).snapshot.blockData));
	}

	void sendChunkTo(ChunkWorldPos position, ClientId clientId)
	{
		//tracef("send chunk to %s %s", position, chunkStorage.getChunk(position).snapshot.blockData.blocks.length);
		connection.sendTo(clientId,
			ChunkDataPacket(position.vector, chunkStorage.getChunk(position).snapshot.blockData));
	}

	void sendToChunkObservers(P)(ChunkWorldPos position, P packet)
	{
		if (auto observerlist = position in chunkObservers)
		{
			connection.sendTo((*observerlist).observers, packet);
		}
	}

	bool isChunkInWorldBounds(ChunkWorldPos position)
	{
		static if (BOUND_WORLD)
		{
			if(position.x<0 || position.y<0 || position.z<0 || position.x>=WORLD_SIZE ||
				position.y>=WORLD_SIZE || position.z>=WORLD_SIZE)
				return false;
		}

		return true;
	}

	void printAdjacent(Chunk* chunk)
	{
		void printChunk(Side side)
		{
			byte[3] offset = sideOffsets[side];
			ivec3 otherPosition = ivec3(chunk.position.x + offset[0],
									chunk.position.y + offset[1],
									chunk.position.z + offset[2]);
			Chunk* c = chunkStorage.getChunk(ChunkWorldPos(otherPosition));
			tracef("%s", c is null ? "null" : "a");
		}

		foreach(s; Side.min..Side.max)
			printChunk(s);
	}

	/// Sends chunk changes to all observers and clears change buffer
	void sendChanges()
	{
		foreach(pair; chunkChanges.byKeyValue)
			sendToChunkObservers(pair.key,
				MultiblockChangePacket(pair.key.vector, pair.value));
		chunkChanges = null;
	}
}
