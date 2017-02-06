/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module test.railroad.railtool;

import voxelman.log;
import voxelman.container.buffer : Buffer;
import voxelman.graphics;
import voxelman.core.config;
import voxelman.core.packets;

import voxelman.blockentity.blockentityman;
import voxelman.blockentity.plugin;
import voxelman.edit.plugin;
import voxelman.graphics.plugin;
import voxelman.net.plugin;
import voxelman.world.blockentity;
import voxelman.world.clientworld;
import voxelman.worldinteraction.plugin;

import voxelman.math;
import voxelman.world.storage;
import voxelman.edit.tools.itool;

import test.railroad.plugin;
import test.railroad.mesh;
import test.railroad.utils;

enum RailOrientation
{
	x,
	z,
	xzSameSign, //xneg-zneg, xpos-zpos
	xzOppSign // xneg-zpos, xpos-zneg
}

final class RailTool : ITool
{
	ClientWorld clientWorld;
	BlockEntityManager blockEntityManager;
	NetClientPlugin connection;
	WorldInteractionPlugin worldInteraction;

	BlockWorldPos startingPos;
	RailSegment segment;
	BlockWorldPos cursorPos;

	RailOrientation cursorOrientation;
	uint curLength;
	RailPos minPos;

	enum EditState
	{
		none,
		placing,
		removing
	}
	EditState state;

	this(ClientWorld clientWorld, BlockEntityManager blockEntityManager,
		NetClientPlugin connection, WorldInteractionPlugin worldInteraction)
	{
		this.clientWorld = clientWorld;
		this.blockEntityManager = blockEntityManager;
		this.connection = connection;
		this.worldInteraction = worldInteraction;
		name = "test.entity.place_rail";
	}

	override void onUpdate()
	{
		updateCursorStartingPos();
	}

	override void onRender(GraphicsPlugin graphics) {
		if (worldInteraction.cameraInSolidBlock) return;
		if (!worldInteraction.cursorHit) return;

		final switch(state) {
			case EditState.none:
				drawLine(cursorPos, cursorPos, graphics, Colors.white);
				break;
			case EditState.placing:
				drawLine(startingPos, cursorPos, graphics, Colors.green);
				break;
			case EditState.removing:
				drawLine(startingPos, cursorPos, graphics, Colors.red);
				break;
		}
	}

	void drawLine(BlockWorldPos start, BlockWorldPos end,
		GraphicsPlugin graphics, Colors color)
	{
		final switch(cursorOrientation) {
			case RailOrientation.x:
				auto railPos1 = RailPos(start);
				auto railPos2 = RailPos(end);
				short minX = min(railPos1.x, railPos2.x);
				short maxX = cast(short)(max(railPos1.x, railPos2.x) + 1);
				minPos = railPos1;
				minPos.x = minX;
				curLength = (maxX - minX);
				int length = curLength * RAIL_TILE_SIZE;
				vec3 cubePos = vec3(minX*RAIL_TILE_SIZE, start.y+0.25, railPos1.z*RAIL_TILE_SIZE+RAIL_TILE_SIZE/2-0.25);
				graphics.debugBatch.putCube(cubePos+vec3(0,0,1), vec3(length, 0.5, 0.5), color, true);
				graphics.debugBatch.putCube(cubePos-vec3(0,0,1), vec3(length, 0.5, 0.5), color, true);
				break;
			case RailOrientation.z:
				auto railPos1 = RailPos(start);
				auto railPos2 = RailPos(end);
				short minZ = min(railPos1.z, railPos2.z);
				short maxZ = cast(short)(max(railPos1.z, railPos2.z) + 1);
				minPos = railPos1;
				minPos.z = minZ;
				curLength = (maxZ - minZ);
				int length = curLength * RAIL_TILE_SIZE;
				vec3 cubePos = vec3(railPos1.x*RAIL_TILE_SIZE+RAIL_TILE_SIZE/2-0.25, start.y+0.25, minZ*RAIL_TILE_SIZE);
				graphics.debugBatch.putCube(cubePos+vec3(1,0,0), vec3(0.5, 0.5, length), color, true);
				graphics.debugBatch.putCube(cubePos-vec3(1,0,0), vec3(0.5, 0.5, length), color, true);
				break;
			case RailOrientation.xzSameSign:

				break;
			case RailOrientation.xzOppSign:

				break;
		}
	}

	override void onShowDebug() {
		import voxelman.utils.textformatter;
		igTextf("Orientation: %s", cursorOrientation);
	}

	override void onMainActionPress() {
		if (state != EditState.none) return;
		if (!worldInteraction.cursorHit) return;
		state = EditState.removing;
		startingPos = cursorPos;
	}

	override void onMainActionRelease() {
		if (state != EditState.removing) return;
		state = EditState.none;

		if (worldInteraction.cursorHit)
		{
			connection.send(EditRailLinePacket(minPos, curLength, cursorOrientation, RailEditOp.remove));
		}
	}

	private void updateCursorStartingPos() {
		if (worldInteraction.cameraInSolidBlock) return;

		cursorPos = worldInteraction.sideBlockPos;

		RailData railOnGround = getRailAt(RailPos(worldInteraction.blockPos),
			blockEntityManager.getId("rail"),
			clientWorld.worldAccess, clientWorld.entityAccess);

		if (!railOnGround.empty)
		{
			cursorPos = worldInteraction.blockPos;
		}
	}

	override void onSecondaryActionPress() {
		if (state != EditState.none) return;
		if (!worldInteraction.cursorHit) return;
		state = EditState.placing;
		startingPos = cursorPos;
	}

	override void onSecondaryActionRelease() {
		if (state != EditState.placing) return;
		state = EditState.none;

		if (worldInteraction.cursorHit)
		{
			connection.send(EditRailLinePacket(minPos, curLength, cursorOrientation, RailEditOp.add));
		}
	}

	override void onRotateAction() {
		cursorOrientation = cast(RailOrientation)((cursorOrientation + 1) % 2);
	}
}
