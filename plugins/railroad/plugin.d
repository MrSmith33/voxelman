/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module railroad.plugin;

import datadriven;
import pluginlib;
import voxelman.core.config;
import voxelman.core.events;
import voxelman.core.packets;
import voxelman.log;

import voxelman.blockentity.blockentityman;
import voxelman.command.plugin;
import voxelman.blockentity.plugin;
import voxelman.edit.plugin;
import voxelman.entity.plugin;
import voxelman.eventdispatcher.plugin;
import voxelman.graphics.plugin;
import voxelman.net.plugin;
import voxelman.world.clientworld;
import voxelman.world.serverworld;
import voxelman.world.storage;
import voxelman.worldinteraction.plugin;

import voxelman.world.block;
import voxelman.math;
import voxelman.geometry;

import voxelman.world.blockentity;

import railroad.rail.mesh;
import railroad.rail.utils;
import railroad.rail.railtool;
import railroad.rail.railgraph;
import railroad.rail.packets;

import railroad.wagon.wagontool;
import railroad.wagon.packets;
import railroad.wagon.wagon;


final class RailroadPluginClient : IPlugin
{
	mixin IdAndSemverFrom!"railroad.plugininfo";
	mixin RailroadPluginCommon;

	ClientWorld clientWorld;
	NetClientPlugin connection;
	WorldInteractionPlugin worldInteraction;
	GraphicsPlugin graphics;

	Batch batch;
	EntityManager* eman;

	override void registerResources(IResourceManagerRegistry resmanRegistry) {
		retreiveBlockEntityManager(resmanRegistry);
		auto components = resmanRegistry.getResourceManager!EntityComponentRegistry;
		eman = components.eman;
		eman.registerComponent!WagonClientComponent();
	}

	override void preInit() {
		import voxelman.globalconfig;
		import voxelman.model.obj;
		import voxelman.model.ply;
		import voxelman.model.mesh;
		import voxelman.model.utils;
		import voxelman.world.mesh.chunkmesh;
		try{
			railMeshes[0] = readPlyFile!RailVertexT(BUILD_TO_ROOT_PATH~"res/model/rail1.ply");
			railMeshes[1] = readPlyFile!RailVertexT(BUILD_TO_ROOT_PATH~"res/model/rail2.ply");
			railMeshes[2] = readPlyFile!RailVertexT(BUILD_TO_ROOT_PATH~"res/model/rail3.ply");
		}
		catch(Exception e){
			warningf("Error reading model, %s", e);
		}
	}

	override void init(IPluginManager pluginman)
	{
		worldInteraction = pluginman.getPlugin!WorldInteractionPlugin;
		clientWorld = pluginman.getPlugin!ClientWorld;
		graphics = pluginman.getPlugin!GraphicsPlugin;

		connection = pluginman.getPlugin!NetClientPlugin;
		connection.registerPacket!PlaceRailPacket;
		connection.registerPacket!EditRailLinePacket;
		connection.registerPacket!CreateWagonPacket;

		auto railTool = new RailTool(clientWorld, blockEntityManager,
			connection, worldInteraction);

		auto wagonTool = new WagonTool(clientWorld, blockEntityManager,
			connection, worldInteraction);

		auto editPlugin = pluginman.getPlugin!EditPlugin;
		editPlugin.registerTool(railTool);
		editPlugin.registerTool(wagonTool);

		auto evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&drawEntities);
	}

	void drawEntities(ref RenderSolid3dEvent event)
	{
		batch.reset();
		auto query = eman.query!WagonClientComponent;
		foreach (row; query)
		{
			if (row.wagonClientComponent_0.dimension == clientWorld.currentDimension)
			{
				batch.putCube(row.wagonClientComponent_0.dimPos - vec3(0.5,0.5,0.5), vec3(1,1,1), Colors.black, true);
			}
		}
		graphics.draw(batch);
	}
}

final class RailroadPluginServer : IPlugin
{
	mixin IdAndSemverFrom!"railroad.plugininfo";
	mixin RailroadPluginCommon;

	WagonLogicServer wagonLogic;

	NetServerPlugin connection;
	ServerWorld serverWorld;
	BlockEntityServer blockEntityPlugin;
	RailGraph railGraph;

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		wagonLogic.registerResources(resmanRegistry);
		auto ioman = resmanRegistry.getResourceManager!IoManager;
		ioman.registerWorldLoadSaveHandlers(&railGraph.read, &railGraph.write);
		retreiveBlockEntityManager(resmanRegistry);
	}

	override void init(IPluginManager pluginman)
	{
		connection = pluginman.getPlugin!NetServerPlugin;
		connection.registerPacket!PlaceRailPacket(&handlePlaceRailPacket);
		connection.registerPacket!EditRailLinePacket(&handleEditRailLinePacket);
		connection.registerPacket!CreateWagonPacket(&wagonLogic.handleCreateWagonPacket);

		serverWorld = pluginman.getPlugin!ServerWorld;
		blockEntityPlugin = pluginman.getPlugin!BlockEntityServer;

		wagonLogic.entityPlugin = pluginman.getPlugin!EntityPluginServer;
		wagonLogic.railGraph = &railGraph;

		auto evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&wagonLogic.process);

		auto command = pluginman.getPlugin!CommandPluginServer;
		command.registerCommand("remove_wagons", &handleRemoveWagons);
	}

	private void handleRemoveWagons(CommandParams params)
	{
		wagonLogic.removeWagons;
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
		final switch(packet.orientation) {
			case RailOrientation.x:
				RailData railData = RailData(RailSegment.xpos);
				foreach(dx; 0..packet.length)
				{
					RailPos railPos = packet.from;
					railPos.x += dx;
					editRail(railPos, railData, packet.editOp);
				}
				break;
			case RailOrientation.z:
				RailData railData = RailData(RailSegment.zneg);
				foreach(dz; 0..packet.length)
				{
					RailPos railPos = packet.from;
					railPos.z += dz;
					editRail(railPos, railData, packet.editOp);
				}
				break;
			case RailOrientation.xzSameSign:
				bool topSide = packet.diagonalRailSide == DiagonalRailSide.zneg;
				RailSegment[2] sides = [RailSegment.xposZpos, RailSegment.xnegZneg];
				ivec2[2] increments = [ivec2(1, 0), ivec2(0, -1)];
				placeDiagonalRail(topSide, packet.from, sides, increments, packet.length, packet.editOp);
				break;
			case RailOrientation.xzOppSign:
				bool topSide = packet.diagonalRailSide == DiagonalRailSide.zneg;
				RailSegment[2] sides = [RailSegment.xnegZpos, RailSegment.xposZneg];
				ivec2[2] increments = [ivec2(0, 1), ivec2(1, 0)];
				placeDiagonalRail(topSide, packet.from, sides, increments, packet.length, packet.editOp);
				break;
		}
	}

	private void placeDiagonalRail(bool topSide, RailPos railPos, RailSegment[2] sides, ivec2[2] increments, size_t length, RailEditOp editOp)
	{
		foreach(i; 0..length)
		{
			RailData railData = RailData(sides[cast(size_t)topSide]);
			editRail(railPos, railData, editOp);

			auto inc = increments[cast(size_t)topSide];
			railPos.x += inc.x;
			railPos.z += inc.y;
			topSide = !topSide;
		}
	}

	void editRail(const RailPos railPos, const RailData railData, RailEditOp editOp = RailEditOp.add)
	{
		ChunkWorldPos cwp = railPos.chunkPos();
		ushort railEntityId = blockEntityManager.getId("rail");

		RailData railOnGround = getRailAt(railPos, railEntityId,
			serverWorld.worldAccess, serverWorld.entityAccess);

		RailData edited = railOnGround;
		edited.editRail(railData, editOp);

		// Adding existing rail segment / removing non-existing
		if (railOnGround == edited) return;

		railGraph.onRailEdit(railPos, railData, editOp);

		if (!railOnGround.empty)
		{
			BlockWorldPos delPos = railPos.deletePos;
			WorldBox changedBox = removeEntity(delPos, blockEntityPlugin.blockEntityInfos,
				serverWorld.worldAccess, serverWorld.entityAccess, BlockId(1));
			connection.sendTo(serverWorld.chunkObserverManager.getChunkObservers(cwp),
				RemoveBlockEntityPacket(delPos.vector));
		}

		if (edited.empty) return;

		WorldBox blockBox = edited.boundingBox(railPos);
		ulong payload = payloadFromIdAndEntityData(railEntityId, edited.data);

		placeEntity(blockBox, payload, serverWorld.worldAccess, serverWorld.entityAccess);

		connection.sendTo(serverWorld.chunkObserverManager.getChunkObservers(cwp),
			PlaceBlockEntityPacket(blockBox, payload));
	}
}

mixin template RailroadPluginCommon()
{
	BlockEntityManager blockEntityManager;
	void retreiveBlockEntityManager(IResourceManagerRegistry resmanRegistry)
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
