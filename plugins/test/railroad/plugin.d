/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module test.railroad.plugin;

import std.experimental.logger;
import pluginlib;
import voxelman.container.buffer;
import voxelman.core.config;
import voxelman.core.packets;

import voxelman.edit.plugin;
import voxelman.graphics.plugin;
import voxelman.net.plugin;
import voxelman.world.clientworld;
import voxelman.world.plugin;
import voxelman.worldinteraction.plugin;
import voxelman.blockentity.plugin;

import voxelman.blockentity.blockentityaccess;

import voxelman.block.utils;
import voxelman.utils.math;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.worldbox;

import voxelman.blockentity.blockentityaccess;
import voxelman.world.storage.worldaccess;

import test.railroad.mesh;
public import test.railroad.utils;

shared static this()
{
	pluginRegistry.regClientPlugin(new TrainsPluginClient);
	pluginRegistry.regServerPlugin(new TrainsPluginServer);
}


struct PlaceRailPacket
{
	RailPos pos;
	ubyte data;
}


final class TrainsPluginClient : IPlugin
{
	mixin IdAndSemverFrom!(test.railroad.plugininfo);
	mixin TrainsPluginCommon;

	NetClientPlugin connection;
	WorldInteractionPlugin worldInteraction;
	GraphicsPlugin graphics;
	ClientWorld clientWorld;

	RailSegment segment;
	BlockWorldPos placePos;

	override void preInit() {
		import voxelman.globalconfig;
		import voxelman.model.obj;
		import voxelman.model.ply;
		import voxelman.model.mesh;
		import voxelman.model.utils;
		import voxelman.core.chunkmesh;
		try{
			railMeshes[0] = cast(MeshVertex[])readPlyFile(BUILD_TO_ROOT_PATH~"res/model/rail1.ply");
			railMeshes[1] = cast(MeshVertex[])readPlyFile(BUILD_TO_ROOT_PATH~"res/model/rail2.ply");
			railMeshes[2] = cast(MeshVertex[])readPlyFile(BUILD_TO_ROOT_PATH~"res/model/rail3.ply");
		}
		catch(Exception e){
			warningf("Error reading model, %s", e);
		}
	}

	override void init(IPluginManager pluginman)
	{
		auto railTool = new class ITool
		{
			this() { name = "test.entity.place_rail"; }
			override void onUpdate()
			{
				if (!worldInteraction.cameraInSolidBlock)
				{
					auto railData = RailData(segment);

					auto blockId = worldInteraction.pickBlock();
					placePos = worldInteraction.sideBlockPos;

					RailData railOnGround = getRailAt(RailPos(worldInteraction.blockPos),
						blockEntityManager.getId("rail"),
						clientWorld.worldAccess, clientWorld.entityAccess);

					if (!railOnGround.empty)
					{
						placePos = worldInteraction.blockPos;
						//drawSolidityDebug(graphics.debugBatch, railOnGround, placePos);
					}

					WorldBox box = railData.boundingBox(placePos);

					graphics.debugBatch.putCube(vec3(box.position) - cursorOffset,
						vec3(1,1,1) + cursorOffset, Colors.blue, false);

					graphics.debugBatch.putCube(vec3(box.position) - cursorOffset,
						vec3(box.size) + cursorOffset, Colors.green, false);

					auto triBuffer = Buffer!ColoredVertex(graphics.debugBatch.triBuffer,
						graphics.debugBatch.triBuffer.length);

					putRailMesh(triBuffer, box.position, railData);

					graphics.debugBatch.triBuffer = triBuffer.data;

					import derelict.imgui.imgui;
					import voxelman.utils.textformatter;

					igBegin("Debug");
						igTextf("Segment: %s s %s o %s m %s r %s", segment,
							railSegmentSizes[segment], railSegmentOffsets[segment],
							railSegmentMeshId[segment], railSegmentMeshRotation[segment]);
					igEnd();
				}
			}
			override void onSecondaryActionRelease() {
				connection.send(PlaceRailPacket(RailPos(placePos), RailData(segment).data));
			}

			override void onMainActionRelease() {
				auto blockId = worldInteraction.pickBlock();
				if (isBlockEntity(blockId)) {
					connection.send(RemoveBlockEntityPacket(worldInteraction.blockPos.vector.arrayof));
				}
			}
			override void onRotateAction() {
				rotateSegment(segment);
			}
		};
		worldInteraction = pluginman.getPlugin!WorldInteractionPlugin;
		graphics = pluginman.getPlugin!GraphicsPlugin;
		clientWorld = pluginman.getPlugin!ClientWorld;

		auto editPlugin = pluginman.getPlugin!EditPlugin;
		editPlugin.registerTool(railTool);

		connection = pluginman.getPlugin!NetClientPlugin;
		connection.registerPacket!PlaceRailPacket;
	}
}

final class TrainsPluginServer : IPlugin
{
	mixin IdAndSemverFrom!(test.railroad.plugininfo);
	mixin TrainsPluginCommon;

	NetServerPlugin connection;
	ServerWorld serverWorld;
	BlockEntityServer blockEntityPlugin;

	override void init(IPluginManager pluginman)
	{
		connection = pluginman.getPlugin!NetServerPlugin;
		connection.registerPacket!PlaceRailPacket(&handlePlaceRailPacket);
		serverWorld = pluginman.getPlugin!ServerWorld;
		blockEntityPlugin = pluginman.getPlugin!BlockEntityServer;
	}

	void handlePlaceRailPacket(ubyte[] packetData, ClientId clientId)
	{
		auto packet = unpackPacket!PlaceRailPacket(packetData);
		RailPos railPos = packet.pos;
		ChunkWorldPos cwp = railPos.chunkPos();
		RailData railData = RailData(packet.data);
		ushort railEntityId = blockEntityManager.getId("rail");

		RailData railOnGround = getRailAt(railPos, railEntityId,
			serverWorld.worldAccess, serverWorld.entityAccess);

		if (!railOnGround.empty)
		{
			WorldBox oldBox = railData.boundingBox(railPos);
			BlockWorldPos delPos = railPos.deletePos;

			RailData combined = railOnGround;
			combined.addRail(railData); // combine rails

			// Adding existing rail segment
			if (railOnGround == combined)
				return;

			WorldBox changedBox = removeEntity(delPos, blockEntityPlugin.blockEntityInfos,
				serverWorld.worldAccess, serverWorld.entityAccess, BlockId(1));
			connection.sendTo(serverWorld.chunkObserverManager.getChunkObservers(cwp),
				RemoveBlockEntityPacket(delPos.vector.arrayof));
			railData = combined;
		}

		WorldBox blockBox = railData.boundingBox(railPos);
		ulong payload = payloadFromIdAndEntityData(railEntityId, railData.data);

		placeEntity(blockBox, payload, serverWorld.worldAccess, serverWorld.entityAccess);

		connection.sendTo(serverWorld.chunkObserverManager.getChunkObservers(cwp),
			PlaceBlockEntityPacket(blockBox, payload));
		//infof("Place rail %s %s", packet.pos, blockBox);
	}
}

mixin template TrainsPluginCommon()
{
	BlockEntityManager blockEntityManager;
	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		blockEntityManager = resmanRegistry.getResourceManager!BlockEntityManager;
		blockEntityManager.regBlockEntity("rail")
			.boxHandler(&railBoxHandler)
			.meshHandler(&makeRailMesh)
			.color([128, 128, 128])
			.sideSolidity(&railSideSolidity);
	}
}

WorldBox railBoxHandler(BlockWorldPos bwp, BlockEntityData data)
{
	return RailData(data).boundingBox(bwp);
}

Solidity railSideSolidity(Side side, ivec3 chunkPos, ivec3 entityPos, BlockEntityData data)
{
	if (side == Side.bottom)
	{
		return RailData(data).bottomSolidity(calcBlockTilePos(chunkPos));
	}
	return Solidity.transparent;
}
