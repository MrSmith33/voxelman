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

enum RailEditOp
{
	add,
	remove
}

struct EditRailLinePacket
{
	RailPos from;
	size_t length;
	RailOrientation orientation;
	RailEditOp editOp;
}

final class RailroadPluginClient : IPlugin
{
	mixin IdAndSemverFrom!"test.railroad.plugininfo";
	mixin RailroadPluginCommon;

	ClientWorld clientWorld;
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
		clientWorld = pluginman.getPlugin!ClientWorld;

		connection = pluginman.getPlugin!NetClientPlugin;
		connection.registerPacket!PlaceRailPacket;
		connection.registerPacket!EditRailLinePacket;

		auto railTool = new RailTool(clientWorld, blockEntityManager,
			connection, worldInteraction);

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
		connection.registerPacket!EditRailLinePacket(&handleEditRailLinePacket);
		serverWorld = pluginman.getPlugin!ServerWorld;
		blockEntityPlugin = pluginman.getPlugin!BlockEntityServer;
	}

	void handlePlaceRailPacket(ubyte[] packetData, SessionId sessionId)
	{
		auto packet = unpackPacket!PlaceRailPacket(packetData);
		RailPos railPos = packet.pos;
		RailData railData = RailData(packet.data);
		editRail(railPos, railData);
	}

	void handleEditRailLinePacket(ubyte[] packetData, SessionId sessionId)
	{
		auto packet = unpackPacket!EditRailLinePacket(packetData);
		RailPos from = packet.from;
		final switch(packet.orientation) {
			case RailOrientation.x:
				RailData railData = RailData(RailSegment.xpos);
				foreach(dx; 0..packet.length)
				{
					RailPos railPos = from;
					railPos.x += dx;
					editRail(railPos, railData, packet.editOp);
				}
				break;
			case RailOrientation.z:
				RailData railData = RailData(RailSegment.zneg);
				foreach(dz; 0..packet.length)
				{
					RailPos railPos = from;
					railPos.z += dz;
					editRail(railPos, railData, packet.editOp);
				}
				break;
			case RailOrientation.xzSameSign:
				break;
			case RailOrientation.xzOppSign:
				break;
		}
	}

	void editRail(RailPos railPos, RailData railData, RailEditOp editOp = RailEditOp.add)
	{
		ChunkWorldPos cwp = railPos.chunkPos();
		ushort railEntityId = blockEntityManager.getId("rail");

		RailData railOnGround = getRailAt(railPos, railEntityId,
			serverWorld.worldAccess, serverWorld.entityAccess);

		if (railOnGround.empty && editOp == RailEditOp.remove) return;

		if (!railOnGround.empty)
		{
			RailData modified = railOnGround;
			final switch(editOp)
			{
				case RailEditOp.add:
					modified.addRail(railData); // combine rails
					break;
				case RailEditOp.remove:
					modified.removeRail(railData); // remove rails
					break;
			}

			// Adding existing rail segment
			if (railOnGround == modified)
				return;

			BlockWorldPos delPos = railPos.deletePos;
			WorldBox changedBox = removeEntity(delPos, blockEntityPlugin.blockEntityInfos,
				serverWorld.worldAccess, serverWorld.entityAccess, BlockId(1));
			connection.sendTo(serverWorld.chunkObserverManager.getChunkObservers(cwp),
				RemoveBlockEntityPacket(delPos.vector));
			railData = modified;
		}

		if (railData.empty) return;

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
	auto railData = RailData(data);
	if (railData.bottomSolidity(calcBlockTilePos(chunkPos)))
	{
		if (railData.isSlope)
			return railSlopeShapes[railData.data - SLOPE_RAIL_BIT];
		else
			return railBlockShape;
	}
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
const BlockShape[4] railSlopeShapes = [
	BlockShape([ // zneg
		ShapeSideMask.full, ShapeSideMask.empty, ShapeSideMask.empty,
		ShapeSideMask.empty, ShapeSideMask.empty, ShapeSideMask.full],
		0b_0011_1111, true, true),
	BlockShape([ // xneg
		ShapeSideMask.empty, ShapeSideMask.empty, ShapeSideMask.empty,
		ShapeSideMask.full, ShapeSideMask.empty, ShapeSideMask.full],
		0b_0101_1111, true, true),
	BlockShape([ // zpos
		ShapeSideMask.empty, ShapeSideMask.full, ShapeSideMask.empty,
		ShapeSideMask.empty, ShapeSideMask.empty, ShapeSideMask.full],
		0b_1100_1111, true, true),
	BlockShape([ // xpos
		ShapeSideMask.empty, ShapeSideMask.empty, ShapeSideMask.full,
		ShapeSideMask.empty, ShapeSideMask.empty, ShapeSideMask.full],
		0b_1010_1111, true, true)];
