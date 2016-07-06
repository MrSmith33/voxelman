/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module test.railroad.plugin;

import std.experimental.logger;
import pluginlib;
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
	RailPos railPos;
	RailData railData = RailData(1);

	override void preInit() {
		import voxelman.globalconfig;
		import voxelman.model.obj;
		import voxelman.model.ply;
		import voxelman.model.mesh;
		import voxelman.model.utils;
		import voxelman.core.chunkmesh;
		try{
			railMesh_1 = cast(MeshVertex[])readPlyFile(BUILD_TO_ROOT_PATH~"res/model/rail1.ply");
			railMesh_2 = cast(MeshVertex[])readPlyFile(BUILD_TO_ROOT_PATH~"res/model/rail2.ply");
			railMesh_3 = cast(MeshVertex[])readPlyFile(BUILD_TO_ROOT_PATH~"res/model/rail3.ply");
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
				railPos = RailPos(worldInteraction.sideBlockPos);
				if (!worldInteraction.cameraInSolidBlock)
				{
					WorldBox box = railData.boundingBox(worldInteraction.sideBlockPos);
					graphics.debugBatch.putCube(vec3(box.position) - cursorOffset,
						vec3(box.size) + cursorOffset, Colors.green, false);
				}
			}
			override void onSecondaryActionRelease() {
				connection.send(PlaceRailPacket(railPos, railData.data));
			}

			override void onMainActionRelease() {
				auto blockId = worldInteraction.pickBlock();
				if (isBlockEntity(blockId)) {
					connection.send(RemoveBlockEntityPacket(worldInteraction.blockPos.vector.arrayof));
				}
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

	override void init(IPluginManager pluginman)
	{
		connection = pluginman.getPlugin!NetServerPlugin;
		connection.registerPacket!PlaceRailPacket(&handlePlaceRailPacket);
		serverWorld = pluginman.getPlugin!ServerWorld;
	}

	void handlePlaceRailPacket(ubyte[] packetData, ClientId clientId)
	{
		auto packet = unpackPacket!PlaceRailPacket(packetData);
		//infof("Place rail %s", packet.pos);
		RailPos railPos = packet.pos;
		RailData railData = RailData(packet.data);

		BlockWorldPos bwp = railPos.toBlockWorldPos;
		WorldBox blockBox = railData.boundingBox(bwp);

		ulong payload = payloadFromIdAndEntityData(
			blockEntityManager.getId("rail"), packet.data);

		placeEntity(blockBox, payload,
			serverWorld.worldAccess, serverWorld.entityAccess);

		ChunkWorldPos cwp = railPos.chunkPos();
		connection.sendTo(serverWorld.chunkObserverManager.getChunkObservers(cwp),
			PlaceBlockEntityPacket(blockBox, payload));
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

Solidity railSideSolidity(Side side)
{
	if (side == Side.bottom) return Solidity.solid;
	return Solidity.transparent;
}
