/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module railroad.wagon.wagon;

import voxelman.log;
import pluginlib;
import datadriven;
import voxelman.math;

import voxelman.core.config;
import voxelman.entity.plugin;
import voxelman.net.plugin;
import voxelman.world.storage;
import voxelman.world.mesh.utils : FaceSide, oppFaceSides;

import railroad.rail.railgraph;
import railroad.rail.utils;
import railroad.wagon.packets;

@Component("railroad.wagon.client", Replication.toClient)
struct WagonClientComponent
{
	vec3 dimPos;
	DimensionId dimension;
}

@Component("railroad.wagon.server", Replication.toDb)
struct WagonServerComponent
{
	RailPos railTilePos;
	RailSegment currentSegment;

	// 0 or 1
	// 0 - from point 1 to point 0
	// 1 - from point 0 to point 1
	ubyte targetConnection;

	float segmentPos = 0; // [0; segmentLength]
	float speed = 5;

	vec3 dimPosition()
	{
		// [0; 1]
		float curSegmentProgress = segmentPos / segmentLengths[currentSegment];

		auto sides = segmentInfos[currentSegment].sides;
		FaceSide startSide = sides[1 - targetConnection];
		FaceSide endSide = sides[targetConnection];

		vec3 startPoint = railTileConnectionPoints[startSide];
		vec3 endPoint = railTileConnectionPoints[endSide];
		vec3 wagonTilePos = lerp(startPoint, endPoint, curSegmentProgress);
		vec3 wagonDimPos = vec3(railTilePos.toBlockWorldPos.xyz) + wagonTilePos;
		return wagonDimPos;
	}

	ChunkWorldPos chunk(vec3 wagonDimPos)
	{
		auto wagonBlock = BlockWorldPos(wagonDimPos, railTilePos.w);
		auto wagonChunk = ChunkWorldPos(wagonBlock);
		return wagonChunk;
	}

	ChunkWorldPos chunk()
	{
		return chunk(dimPosition);
	}
}

struct WagonPos
{
	RailPos railTilePos;
	RailSegment currentSegment;

	// 0 or 1
	// 0 - from point 1 to point 0
	// 1 - from point 0 to point 1
	ubyte targetConnection;

	float segmentPos = 0; // [0; segmentLength]

	vec3 dimPosition()
	{
		// [0; 1]
		float curSegmentProgress = segmentPos / segmentLengths[currentSegment];

		auto sides = segmentInfos[currentSegment].sides;
		FaceSide startSide = sides[1 - targetConnection];
		FaceSide endSide = sides[targetConnection];

		vec3 startPoint = railTileConnectionPoints[startSide];
		vec3 endPoint = railTileConnectionPoints[endSide];
		vec3 wagonTilePos = lerp(startPoint, endPoint, curSegmentProgress);
		vec3 wagonDimPos = vec3(railTilePos.toBlockWorldPos.xyz) + wagonTilePos;
		return wagonDimPos;
	}
}

struct WagonLogicServer
{
	import datadriven;
	EntityManager* eman;
	EntityPluginServer entityPlugin;
	RailGraph* railGraph;

	void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto components = resmanRegistry.getResourceManager!EntityComponentRegistry;
		eman = components.eman;
		eman.registerComponent!WagonClientComponent();
		eman.registerComponent!WagonServerComponent();
	}

	void handleCreateWagonPacket(ubyte[] packetData, SessionId sessionId)
	{
		auto packet = unpackPacket!CreateWagonPacket(packetData);
		createWagon(packet.pos);
	}

	void createWagon(RailPos pos)
	{
		auto rail = pos in railGraph.rails;

		if (rail && !rail.empty)
		{
			RailSegment segment;
			foreach(s; rail.getSegments) {
				segment = s;
				break;
			}

			EntityId eid = eman.eidMan.nextEntityId;
			infof("create wagon %s at %s", eid, pos);
			auto wagon = WagonServerComponent(pos, segment);
			eman.set(eid, wagon);
			entityPlugin.entityObserverManager.addEntity(eid, wagon.chunk);
		}
	}

	void removeWagons()
	{
		foreach(EntityId eid; eman.getComponentStorage!WagonServerComponent.byKey)
			entityPlugin.entityObserverManager.removeEntity(eid);

		eman.getComponentStorage!WagonServerComponent.removeAll;
	}

	void process(ref ProcessComponentsEvent event)
	{
		auto query = eman.query!WagonServerComponent();
		foreach(row; query)
		{
			moveWagon(row.id, *row.wagonServerComponent_0, event.deltaTime);
		}
	}

	void moveWagon(EntityId eid, ref WagonServerComponent wagon, float dt)
	{
		float distance = wagon.speed * dt;

		while (true)
		{
			float segmentLength = segmentLengths[wagon.currentSegment];
			float currentSegmentRemained = segmentLength - wagon.segmentPos;

			if (distance <= currentSegmentRemained)
			{
				wagon.segmentPos += distance;
				break;
			}
			else
			{
				distance -= currentSegmentRemained;
				moveToNextSegment(wagon);
			}
		}

		auto wagonDimPos = wagon.dimPosition;
		//infof("wagon %s %s", eid, wagon);

		entityPlugin.entityObserverManager.updateEntityPos(eid,	wagon.chunk(wagonDimPos));
		eman.set(eid, WagonClientComponent(wagonDimPos, wagon.railTilePos.w));
	}

	void moveToNextSegment(ref WagonServerComponent wagon)
	{
		auto sides = segmentInfos[wagon.currentSegment].sides;
		FaceSide targetDirection = sides[wagon.targetConnection]; // 0-3
		RailPos nextPos = wagon.railTilePos.posInDirection(targetDirection);
		//infof("next rail %s targetDirection %s", nextPos, targetDirection);

		auto rail = nextPos in railGraph.rails;

		if (rail)
		{
			wagon.railTilePos = nextPos;
			auto startSide = oppFaceSides[targetDirection];
			auto avaliableSegments = rail.getSegmentsFromSide(startSide);

			auto length = avaliableSegments.data.length;
			if (length)
			{
				import std.random : uniform;
				wagon.currentSegment = avaliableSegments[uniform(0, length)];
				wagon.segmentPos = 0;
				wagon.targetConnection = cast(ubyte)(1 - segmentInfos[wagon.currentSegment].sideIndicies[startSide]);
				return;
			}
		}

		// return in opposite direction
		wagon.segmentPos = 0;
		wagon.targetConnection = cast(ubyte)(1 - wagon.targetConnection);
	}
}
