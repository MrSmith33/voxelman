/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.edit.tools.filltool;

import voxelman.core.config;
import voxelman.core.packets;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.volume;

import voxelman.client.plugin;
import voxelman.worldinteraction.plugin;
import voxelman.graphics.plugin;
import voxelman.net.plugin;

import voxelman.edit.plugin : ITool;

final class FillTool : ITool
{
	ClientPlugin clientPlugin;
	WorldInteractionPlugin worldInteraction;
	GraphicsPlugin graphics;
	NetClientPlugin connection;

	BlockId currentBlock = 4;
	BlockWorldPos startingPos;
	EditState state;
	Volume selection;

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
		selection = volumeFromCorners(startingPos.vector.xyz, currentCursorPos.vector.xyz, cast(DimentionId)currentCursorPos.w);
		drawSelection();
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
				graphics.debugBatch.putCube(vec3(selection.position), vec3(selection.size), Colors.blue, false);
				break;
			case EditState.removing:
				graphics.debugBatch.putCube(vec3(selection.position), vec3(selection.size), Colors.red, false);
				break;
		}
	}

	override void onMainActionPress() {
		if (!clientPlugin.mouseLocked) return;
		if (state != EditState.none) return;
		if (!worldInteraction.cursorHit) return;
		state = EditState.removing;
		startingPos = currentCursorPos;
		worldInteraction.showCursor = false;
	}

	override void onMainActionRelease() {
		if (!clientPlugin.mouseLocked) return;
		if (state != EditState.removing) return;
		state = EditState.none;
		worldInteraction.showCursor = true;

		if (worldInteraction.cursorHit)
		{
			fillVolume(selection, 1);
		}
	}

	override void onSecondaryActionPress() {
		if (!clientPlugin.mouseLocked) return;
		if (state != EditState.none) return;
		if (!worldInteraction.cursorHit) return;
		state = EditState.placing;
		startingPos = currentCursorPos;
		worldInteraction.showCursor = false;
	}

	override void onSecondaryActionRelease() {
		if (!clientPlugin.mouseLocked) return;
		if (state != EditState.placing) return;
		state = EditState.none;
		worldInteraction.showCursor = true;

		if (worldInteraction.cursorHit)
		{
			fillVolume(selection, currentBlock);
		}
	}

	override void onTertiaryActionRelease() {
		if (!clientPlugin.mouseLocked) return;
		currentBlock = worldInteraction.pickBlock();
	}

	void fillVolume(Volume volume, BlockId blockId)
	{
		connection.send(FillBlockVolumePacket(volume, blockId));
	}
}
