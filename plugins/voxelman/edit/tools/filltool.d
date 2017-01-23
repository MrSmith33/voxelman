/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.edit.tools.filltool;

import voxelman.log;
import voxelman.math;
import voxelman.geometry.cube;
import voxelman.core.config;
import voxelman.core.packets;
import voxelman.world.storage;
import voxelman.world.block.utils;
import voxelman.world.mesh.meshgenerator : SingleBlockMesher;

import voxelman.client.plugin;
import voxelman.worldinteraction.plugin;
import voxelman.graphics.plugin;
import voxelman.net.plugin;

import voxelman.edit.plugin : ITool;

final class FillTool : ITool
{
	WorldInteractionPlugin worldInteraction;
	GraphicsPlugin graphics;
	NetClientPlugin connection;
	BlockInfoTable blockInfos;

	BlockIdAndMeta currentBlock = BlockIdAndMeta(4);
	ubyte currentRotation = 0;

	BlockWorldPos startingPos;
	EditState state;
	WorldBox selection;
	bool showCursor = true;

	SingleBlockMesher blockMesher;

	enum EditState
	{
		none,
		placing,
		removing
	}

	this() { name = "voxelman.edit.fill_tool"; }

	override void onUpdate() {
		if (currentCursorPos.w != startingPos.w)
		{
			startingPos = currentCursorPos;
		}
		selection = worldBoxFromCorners(startingPos.vector.xyz, currentCursorPos.vector.xyz, cast(DimensionId)currentCursorPos.w);
		drawSelection();
		if (showCursor && !worldInteraction.cameraInSolidBlock)
		{
			worldInteraction.drawCursor(worldInteraction.blockPos, Colors.red);
			worldInteraction.drawCursor(worldInteraction.sideBlockPos, Colors.blue);

			blockMesher.meshBlock(blockInfos[currentBlock.id], currentBlock.metadata);
			graphics.debugBatch.putSolidMesh(blockMesher.geometry.data, vec3(worldInteraction.sideBlockPos.xyz));
			blockMesher.reset();
		}
		updateBlockRotation();
	}

	BlockWorldPos currentCursorPos() @property {
		final switch(state) {
			case EditState.none: return worldInteraction.blockPos;
			case EditState.placing:
				return worldInteraction.sideBlockPos;
			case EditState.removing:
				return worldInteraction.blockPos;
		}
	}

	void drawSelection() {
		final switch(state) {
			case EditState.none:
				break;
			case EditState.placing:
				graphics.debugBatch.putCube(vec3(selection.position) - cursorOffset,
					vec3(selection.size) + cursorOffset, Colors.blue, false);
				break;
			case EditState.removing:
				graphics.debugBatch.putCube(vec3(selection.position) - cursorOffset,
					vec3(selection.size) + cursorOffset, Colors.red, false);
				break;
		}
	}

	override void onMainActionPress() {
		if (state != EditState.none) return;
		if (!worldInteraction.cursorHit) return;
		state = EditState.removing;
		startingPos = currentCursorPos;
		showCursor = false;
	}

	override void onMainActionRelease() {
		if (state != EditState.removing) return;
		state = EditState.none;
		showCursor = true;

		if (worldInteraction.cursorHit)
		{
			worldInteraction.fillBox(selection, 1);
		}
	}

	override void onSecondaryActionPress() {
		if (state != EditState.none) return;
		if (!worldInteraction.cursorHit) return;
		state = EditState.placing;
		startingPos = currentCursorPos;
		showCursor = false;
	}

	override void onSecondaryActionRelease() {
		if (state != EditState.placing) return;
		state = EditState.none;
		showCursor = true;

		if (worldInteraction.cursorHit)
		{
			worldInteraction.fillBox(selection, currentBlock.id, currentBlock.metadata);
		}
	}

	override void onTertiaryActionRelease() {
		setCurrentBlock(worldInteraction.pickBlock());
	}

	override void onRotateAction() {
		currentRotation = (currentRotation + 1) % 4;
		updateBlockRotation();
	}

	void updateBlockRotation() {
		if (auto handler = blockInfos[currentBlock.id].rotationHandler)
		{
			CubeSide side = oppSide[sideFromNormal(worldInteraction.hitNormal)];
			handler(currentBlock.metadata, currentRotation, side);
		}
	}

	void setCurrentBlock(BlockIdAndMeta block) {
		currentBlock = block;
	}
}
