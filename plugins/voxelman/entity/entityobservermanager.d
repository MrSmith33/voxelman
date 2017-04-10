/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.entity.entityobservermanager;

import voxelman.log;
import datadriven.api;
import datadriven.entityman;
import voxelman.container.hash.map;
import voxelman.container.hash.set;
import voxelman.world.storage;
import voxelman.entity.plugin;
import voxelman.net.plugin;

struct EntityObserverManager
{
	HashMap!(ulong, HashSet!EntityId) chunkToEntitySet;
	//HashSet!ChunkWorldPos observedEntityChunks;
	HashMap!(EntityId, ChunkWorldPos) entityToChunk;

	void addEntity(EntityId eid, ChunkWorldPos cwp)
	{
		entityToChunk[eid] = cwp;
		addEntityToChunk(eid, cwp);
	}

	void updateEntityPos(EntityId eid, ChunkWorldPos newCwp)
	{
		ChunkWorldPos* cwp = entityToChunk.getOrCreate(eid, newCwp);
		if (*cwp != newCwp)
		{
			removeEntityFromChunk(eid, *cwp);
			addEntityToChunk(eid, newCwp);
		}
		*cwp = newCwp;
	}

	void removeEntity(EntityId eid)
	{
		if (auto cwp = eid in entityToChunk)
		{
			removeEntityFromChunk(eid, *cwp);
			entityToChunk.remove(eid);
		}
	}

	private void addEntityToChunk(EntityId eid, ChunkWorldPos cwp)
	{
		auto entitySetPtr = chunkToEntitySet.getOrCreate(cwp.asUlong);
		entitySetPtr.put(eid);
		//observedEntityChunks.put(cwp);
	}

	private void removeEntityFromChunk(EntityId eid, ChunkWorldPos cwp)
	{
		if (auto set = cwp.asUlong in chunkToEntitySet)
		{
			set.remove(eid);
			if (set.empty)
			{
				chunkToEntitySet.remove(cwp.asUlong);
				//observedEntityChunks.remove(cwp);
			}
		}
	}

	package NetworkSaver netSaver;
	package ChunkObserverManager chunkObserverManager;
	package NetServerPlugin connection;
	package EntityManager* eman;

	void sendEntitiesToObservers()
	{
		connection.sendToAll(ComponentSyncStartPacket());
		foreach(cwp, entities; chunkToEntitySet)
		{
			auto observers = chunkObserverManager.getChunkObservers(ChunkWorldPos(cwp));
			//auto entities = chunkToEntitySet[cwp];
			eman.savePartial(netSaver, entities);
			connection.sendTo(observers, ComponentSyncPacket(netSaver.data));
			netSaver.reset();
		}
		connection.sendToAll(ComponentSyncEndPacket());
	}
}
