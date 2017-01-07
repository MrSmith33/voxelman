/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module test.railroad.railtool;

import voxelman.container.buffer : Buffer;
import voxelman.core.config;
import voxelman.core.packets;

import voxelman.blockentity.plugin;
import voxelman.edit.plugin;
import voxelman.graphics.plugin;
import voxelman.net.plugin;
import voxelman.world.clientworld;
import voxelman.worldinteraction.plugin;

import voxelman.math;
import voxelman.world.storage;

import test.railroad.plugin;
import test.railroad.mesh;
import test.railroad.utils;

final class RailTool : ITool
{
	ClientWorld clientWorld;
	BlockEntityManager blockEntityManager;
	GraphicsPlugin graphics;
	NetClientPlugin connection;
	WorldInteractionPlugin worldInteraction;

	RailSegment segment;
	BlockWorldPos placePos;

	this(ClientWorld clientWorld, BlockEntityManager blockEntityManager,
		GraphicsPlugin graphics, NetClientPlugin connection,
		WorldInteractionPlugin worldInteraction)
	{
		this.clientWorld = clientWorld;
		this.blockEntityManager = blockEntityManager;
		this.graphics = graphics;
		this.connection = connection;
		this.worldInteraction = worldInteraction;
		name = "test.entity.place_rail";
	}

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

			putRailMesh!ColoredVertex(graphics.debugBatch.triBuffer, box.position, railData);

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
			connection.send(RemoveBlockEntityPacket(worldInteraction.blockPos.vector));
		}
	}

	override void onRotateAction() {
		rotateSegment(segment);
	}
}
