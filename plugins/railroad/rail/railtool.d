/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module railroad.rail.railtool;

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

import voxelman.geometry;
import voxelman.math;
import voxelman.world.storage;
import voxelman.edit.tools.itool;

import railroad.plugin;
import railroad.rail.mesh;
import railroad.rail.packets;
import railroad.rail.utils;


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
	DiagonalRailSide diagonalRailSide;
	uint curLength;
	RailPos minPos;
	RailPos maxPos;

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
		name = "entity.place_rail";
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
		CubeSide side0;
		CubeSide side1;

		// little hack to fix preview crossing caused by special combination of offsets
		// happens when two sides with the same sign are emitted.
		bool flipEndOffset = false;

		final switch(cursorOrientation) {
			case RailOrientation.x:
				auto railPos1 = RailPos(start);
				auto railPos2 = RailPos(end);
				short minX = min(railPos1.x, railPos2.x);
				short maxX = max(railPos1.x, railPos2.x);
				minPos.vector = svec4(minX, railPos1.y, railPos1.z, railPos1.w);
				maxPos.vector = svec4(maxX, railPos1.y, railPos1.z, railPos1.w);
				curLength = (maxX - minX) + 1;
				side0 = CubeSide.xneg;
				side1 = CubeSide.xpos;
				break;
			case RailOrientation.z:
				auto railPos1 = RailPos(start);
				auto railPos2 = RailPos(end);
				short minZ = min(railPos1.z, railPos2.z);
				short maxZ = max(railPos1.z, railPos2.z);
				minPos.vector = svec4(railPos1.x, railPos1.y, minZ, railPos1.w);
				maxPos.vector = svec4(railPos1.x, railPos1.y, maxZ, railPos1.w);
				curLength = (maxZ - minZ) + 1;
				side0 = CubeSide.zneg;
				side1 = CubeSide.zpos;
				break;
			case RailOrientation.xzSameSign:
				minPos = RailPos(start);
				vec2 origin = vec2(minPos.xz);
				vec2 cursor = vec2(end.xz) / RAIL_TILE_SIZE - origin - vec2(0,1); // relative to the start of selection
				vec2 dividingAxisVector = vec2(1, -1);

				//     ^ H   /
				//  +---+---& 2 H   | P - values
				//  |  X ^ /|  H    |
				//^ | X   P | H     | 1
				// ^|X   / ^|H      |
				//  +   &1  +       | 0.5
				// L|^ /   X|^      |      +---> X
				//L | P   X | ^     | 0    |
				//  |/ ^ X  |  ^    |      |
				//  &---+---+   ^   |-0.5  v Z
				// /0  L ^       ^
				//    L   ^       ^
				// & - sample vectors of (0, 0), (0.5, -0.5) and (1, -1) give results of 0, 1, 2
				// Points marked as 'P' divide diagonal of rail tile in 4 equal pieces
				// and they have dot results of 0.5 and 1.5
				// Cursor locations between P-points should result in rail pieces marked as 'X'
				// Locations between 0 and 0.5 are L pieces, between 1.5 and 2 are H pieces.
				// dot(dividingAxisVector, cursor) of vec2(1, -1) will give result of 2
				// we substract 0.5 to bring 0 to the first P piece. Second P piece has a value of 1.
				float projection = dot(dividingAxisVector, cursor) - 0.5f;

				// section inside current tile has index of 0
				int cursorSection = cast(int)floor(projection);

				// use length of 0 when no selection
				if (state == EditState.none) cursorSection = 0;

				DiagonalRailSide startSide = cast(DiagonalRailSide)(dot(vec2(1, 1), cursor) < 0);

				DiagonalRailSide endSide = startSide;
				if (cursorSection % 2 != 0) endSide = cast(DiagonalRailSide)(!startSide);

				ivec2 endTile = addDiagonalManhattan(ivec2(minPos.xz), cursorSection, cursorOrientation, startSide);
				maxPos.vector = svec4(cast(short)endTile.x, minPos.y, cast(short)endTile.y, minPos.w);

				if (cursorSection < 0)
				{
					swap(minPos, maxPos);
					cursorSection = -cursorSection;
					if (cursorSection % 2 != 0)
					{
						swap(startSide, endSide);
					}
				}

				diagonalRailSide = startSide;

				// uses manhattan distance
				curLength = cursorSection + 1;

				side0 = [CubeSide.zpos, CubeSide.xneg][startSide];
				side1 = [CubeSide.xpos, CubeSide.zneg][endSide];
				flipEndOffset = startSide == endSide;
				break;
			case RailOrientation.xzOppSign:
				minPos = RailPos(start);
				vec2 origin = vec2(minPos.xz);
				vec2 cursor = vec2(end.xz) / RAIL_TILE_SIZE - origin; // relative to the start of selection
				vec2 dividingAxisVector = vec2(1, 1);
				float projection = dot(dividingAxisVector, cursor) - 0.5f;

				// section inside current tile has index of 0
				int cursorSection = cast(int)floor(projection);

				// use length of 0 when no selection
				if (state == EditState.none) cursorSection = 0;

				DiagonalRailSide startSide = cast(DiagonalRailSide)(dot(vec2(-1, 1), cursor) < 0);

				DiagonalRailSide endSide = startSide;
				if (cursorSection % 2 != 0) endSide = cast(DiagonalRailSide)(!startSide);

				ivec2 endTile = addDiagonalManhattan(ivec2(minPos.xz), cursorSection, cursorOrientation, startSide);
				maxPos.vector = svec4(cast(short)endTile.x, minPos.y, cast(short)endTile.y, minPos.w);

				if (cursorSection < 0)
				{
					swap(minPos, maxPos);
					cursorSection = -cursorSection;
					if (cursorSection % 2 != 0)
					{
						swap(startSide, endSide);
					}
				}

				diagonalRailSide = startSide;

				// uses manhattan distance
				curLength = cursorSection + 1;

				side0 = [CubeSide.xneg, CubeSide.zneg][startSide];
				side1 = [CubeSide.zpos, CubeSide.xpos][endSide];
				break;
		}
		graphics.debugBatch.triBuffer.putRailPreview(minPos, maxPos, side0, side1, flipEndOffset, color);
	}

	override void onShowDebug() {
		//import voxelman.text.textformatter;
		//igTextf("Orientation: %s", cursorOrientation);
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
			connection.send(EditRailLinePacket(minPos, curLength, cursorOrientation, diagonalRailSide, RailEditOp.remove));
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
			connection.send(EditRailLinePacket(minPos, curLength, cursorOrientation, diagonalRailSide, RailEditOp.add));
		}
	}

	override void onRotateAction() {
		cursorOrientation = cast(RailOrientation)((cursorOrientation + 1) % 4);
	}
}
