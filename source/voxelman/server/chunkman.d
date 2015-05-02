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
	ChunkObserverList[ivec3] chunkObservers;
	BlockChange[][ivec3] chunkChanges;

	size_t totalObservedChunks;

	void removeRegionObserver(ClientId clientId)
	{
		auto region = connection.clientStorage[clientId].visibleRegion;
		foreach(chunkCoord; region.chunkCoords)
		{
			removeChunkObserver(chunkCoord, clientId);
		}
	}

	void updateObserverPosition(ClientId clientId)
	{
		ClientInfo* clientInfo = connection.clientStorage[clientId];
		assert(clientInfo, "clientStorage[clientId] is null");
		ChunkRange oldRegion = clientInfo.visibleRegion;
		vec3 cameraPos = clientInfo.pos;
		int viewRadius = clientInfo.viewRadius;

		ivec3 chunkPos = worldToChunkPos(cameraPos);
		ChunkRange newRegion = calcChunkRange(chunkPos, viewRadius);
		if (oldRegion == newRegion) return;

		onClientVisibleRegionChanged(oldRegion, newRegion, clientId);
		connection.clientStorage[clientId].visibleRegion = newRegion;
	}

	void onClientVisibleRegionChanged(ChunkRange oldRegion, ChunkRange newRegion, ClientId clientId)
	{
		if (oldRegion.empty)
		{
			//trace("observe region");
			observeChunks(newRegion.chunkCoords, clientId);
			return;
		}

		auto chunksToRemove = oldRegion.chunksNotIn(newRegion);

		// remove chunks
		foreach(chunkCoord; chunksToRemove)
		{
			removeChunkObserver(chunkCoord, clientId);
		}

		// load chunks
		observeChunks(newRegion.chunksNotIn(oldRegion), clientId);
	}

	void onChunkAdded(Chunk* chunk)
	{
		chunkObservers[chunk.coord] = ChunkObserverList();
	}

	void onChunkLoaded(Chunk* chunk)
	{
		// Send data to observers
		sendChunkToObservers(chunk.coord);
	}

	void onChunkRemoved(Chunk* chunk)
	{
		assert(chunkObservers.get(chunk.coord, ChunkObserverList.init).empty);
		chunkObservers.remove(chunk.coord);
	}

	// world change observer method
	void onChunkModified(Chunk* chunk, BlockChange[] blockChanges)
	{
		chunkChanges[chunk.coord] = chunkChanges.get(chunk.coord, null) ~ blockChanges;
	}

	void observeChunks(R)(R chunkCoords, ClientId clientId)
	{
		import std.range : array;
		import std.algorithm : sort;

		ClientInfo* clientInfo = connection.clientStorage[clientId];
		ivec3 observerPos = ivec3(clientInfo.pos);

		ivec3[] chunksToLoad = chunkCoords.array;
		sort!((a, b) => a.euclidDistSqr(observerPos) < b.euclidDistSqr(observerPos))(chunksToLoad);

		foreach(chunkCoord; chunksToLoad)
		{
			addChunkObserver(chunkCoord, clientId);
		}
	}

	void addChunkObserver(ivec3 coord, ClientId clientId)
	{
		if (!isChunkInWorldBounds(coord)) return;

		bool alreadyLoaded = chunkStorage.loadChunk(coord);

		if (chunkObservers[coord].empty)
		{
			++totalObservedChunks;
		}

		chunkObservers[coord].add(clientId);

		if (alreadyLoaded)
		{
			sendChunkTo(coord, clientId);
		}
	}

	void removeChunkObserver(ivec3 coord, ClientId clientId)
	{
		if (!isChunkInWorldBounds(coord)) return;

		chunkObservers[coord].remove(clientId);

		if (chunkObservers[coord].empty)
		{
			chunkStorage.removeQueue.add(chunkStorage.getChunk(coord));
			--totalObservedChunks;
		}
	}

	void sendChunkToObservers(ivec3 coord)
	{
		//tracef("send chunk to all %s %s", coord, chunkStorage.getChunk(coord).snapshot.blockData.blocks.length);
		sendToChunkObservers(coord,
			ChunkDataPacket(coord, chunkStorage.getChunk(coord).snapshot.blockData));
	}

	void sendChunkTo(ivec3 coord, ClientId clientId)
	{
		//tracef("send chunk to %s %s", coord, chunkStorage.getChunk(coord).snapshot.blockData.blocks.length);
		connection.sendTo(clientId,
			ChunkDataPacket(coord, chunkStorage.getChunk(coord).snapshot.blockData));
	}

	void sendToChunkObservers(P)(ivec3 coord, P packet)
	{
		if (auto observerlist = coord in chunkObservers)
		{
			connection.sendTo((*observerlist).observers, packet);
		}
	}

	bool isChunkInWorldBounds(ivec3 coord)
	{
		static if (BOUND_WORLD)
		{
			if(coord.x<0 || coord.y<0 || coord.z<0 || coord.x>=WORLD_SIZE ||
				coord.y>=WORLD_SIZE || coord.z>=WORLD_SIZE)
				return false;
		}

		return true;
	}

	void printAdjacent(Chunk* chunk)
	{
		void printChunk(Side side)
		{
			byte[3] offset = sideOffsets[side];
			ivec3 otherCoord = ivec3(chunk.coord.x + offset[0],
									chunk.coord.y + offset[1],
									chunk.coord.z + offset[2]);
			Chunk* c = chunkStorage.getChunk(otherCoord);
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
				MultiblockChangePacket(pair.key, pair.value));
		chunkChanges = null;
	}
}
