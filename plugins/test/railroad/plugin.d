/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module test.railroad.plugin;

import voxelman.log;
import pluginlib;
import voxelman.core.config;
import voxelman.core.packets;

import voxelman.blockentity.blockentityman;
import voxelman.blockentity.plugin;
import voxelman.edit.plugin;
import voxelman.graphics.plugin;
import voxelman.net.plugin;
import voxelman.world.clientworld;
import voxelman.world.serverworld;
import voxelman.worldinteraction.plugin;
import voxelman.world.storage;

import voxelman.world.block;
import voxelman.math;
import voxelman.geometry.cube;

import voxelman.world.blockentity;

import test.railroad.mesh;
import test.railroad.utils;
import test.railroad.railtool;


struct PlaceRailPacket
{
	RailPos pos;
	ubyte data;
}


final class RailroadPluginClient : IPlugin
{
	mixin IdAndSemverFrom!"test.railroad.plugininfo";
	mixin RailroadPluginCommon;

	ClientWorld clientWorld;
	GraphicsPlugin graphics;
	NetClientPlugin connection;
	WorldInteractionPlugin worldInteraction;

	override void preInit() {
		import voxelman.globalconfig;
		import voxelman.model.obj;
		import voxelman.model.ply;
		import voxelman.model.mesh;
		import voxelman.model.utils;
		import voxelman.world.mesh.chunkmesh;
		try{
			railMeshes[0] = readPlyFile!MeshVertex(BUILD_TO_ROOT_PATH~"res/model/rail1.ply");
			railMeshes[1] = readPlyFile!MeshVertex(BUILD_TO_ROOT_PATH~"res/model/rail2.ply");
			railMeshes[2] = readPlyFile!MeshVertex(BUILD_TO_ROOT_PATH~"res/model/rail3.ply");
		}
		catch(Exception e){
			warningf("Error reading model, %s", e);
		}
	}

	override void init(IPluginManager pluginman)
	{
		worldInteraction = pluginman.getPlugin!WorldInteractionPlugin;
		graphics = pluginman.getPlugin!GraphicsPlugin;
		clientWorld = pluginman.getPlugin!ClientWorld;

		connection = pluginman.getPlugin!NetClientPlugin;
		connection.registerPacket!PlaceRailPacket;

		auto railTool = new RailTool(clientWorld, blockEntityManager,
			graphics, connection, worldInteraction);

		auto editPlugin = pluginman.getPlugin!EditPlugin;
		editPlugin.registerTool(railTool);
	}
}

final class RailroadPluginServer : IPlugin
{
	mixin IdAndSemverFrom!"test.railroad.plugininfo";
	mixin RailroadPluginCommon;

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

	void handlePlaceRailPacket(ubyte[] packetData, SessionId sessionId)
	{
		auto packet = unpackPacket!PlaceRailPacket(packetData);
		RailPos railPos = packet.pos;
		RailData railData = RailData(packet.data);
		placeRail(railPos, railData);
	}

	void placeRail(RailPos railPos, RailData railData)
	{
		ChunkWorldPos cwp = railPos.chunkPos();
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
				RemoveBlockEntityPacket(delPos.vector));
			railData = combined;
		}

		WorldBox blockBox = railData.boundingBox(railPos);
		ulong payload = payloadFromIdAndEntityData(railEntityId, railData.data);

		placeEntity(blockBox, payload, serverWorld.worldAccess, serverWorld.entityAccess);

		connection.sendTo(serverWorld.chunkObserverManager.getChunkObservers(cwp),
			PlaceBlockEntityPacket(blockBox, payload));
	}
}

mixin template RailroadPluginCommon()
{
	BlockEntityManager blockEntityManager;
	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		blockEntityManager = resmanRegistry.getResourceManager!BlockEntityManager;
		blockEntityManager.regBlockEntity("rail")
			.boxHandler(&railBoxHandler)
			.meshHandler(&makeRailMesh)
			.color([128, 128, 128])
			.blockShapeHandler(&railBlockShapeHandler)
			.sideSolidity(&railSideSolidity)
			.debugHandler(&railDebugHandler);
	}
}

WorldBox railBoxHandler(BlockWorldPos bwp, BlockEntityData data)
{
	return RailData(data).boundingBox(bwp);
}

Solidity railSideSolidity(CubeSide side, ivec3 chunkPos, ivec3 entityPos, BlockEntityData data)
{
	if (side == CubeSide.yneg)
	{
		return RailData(data).bottomSolidity(calcBlockTilePos(chunkPos));
	}
	return Solidity.transparent;
}

BlockShape railBlockShapeHandler(ivec3 chunkPos, ivec3 entityPos, BlockEntityData data)
{
	if (RailData(data).bottomSolidity(calcBlockTilePos(chunkPos)))
		return railBlockShape;
	else
		return emptyShape;
}

const ShapeSideMask[6] railShapeSides = [
	ShapeSideMask.empty,
	ShapeSideMask.empty,
	ShapeSideMask.empty,
	ShapeSideMask.empty,
	ShapeSideMask.empty,
	ShapeSideMask.full]; // bottom is full

const BlockShape railBlockShape = BlockShape(railShapeSides, 0b_0000_1111, true, true);
