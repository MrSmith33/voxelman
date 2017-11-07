/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module railroad.wagon.wagontool;

import voxelman.log;
import voxelman.math;

import voxelman.blockentity.blockentityman;

import voxelman.edit.plugin;
import voxelman.edit.tools.itool;

import voxelman.graphics.plugin;
import voxelman.net.plugin;

import voxelman.world.blockentity;
import voxelman.world.clientworld;
import voxelman.world.storage;
import voxelman.worldinteraction.plugin;

import railroad.rail.utils;
import railroad.wagon.packets;

final class WagonTool : ITool
{
	ClientWorld clientWorld;
	BlockEntityManager blockEntityManager;
	NetClientPlugin connection;
	WorldInteractionPlugin worldInteraction;

	this(ClientWorld clientWorld, BlockEntityManager blockEntityManager,
		NetClientPlugin connection, WorldInteractionPlugin worldInteraction)
	{
		this.clientWorld = clientWorld;
		this.blockEntityManager = blockEntityManager;
		this.connection = connection;
		this.worldInteraction = worldInteraction;
		name = "entity.wagon_tool";
	}

	override void onRender(GraphicsPlugin renderer) {
		if (isRailHovered)
		{
			auto box = RailPos(worldInteraction.blockPos).toBlockBox;
			renderer.debugBatch.putCube(vec3(box.position) - cursorOffset,
				vec3(box.size) + cursorOffset, Colors.yellow, false);
		}
	}

	override void onSecondaryActionRelease() {
		if (isRailHovered) connection.send(CreateWagonPacket(RailPos(worldInteraction.blockPos)));
	}

	bool isRailHovered()
	{
		return isEntityUnderCursor("rail");
	}

	bool isEntityUnderCursor(string entityName)
	{
		auto block = worldInteraction.pickBlock();
		auto bwp = worldInteraction.blockPos;
		auto cwp = ChunkWorldPos(bwp);

		if (isBlockEntity(block.id))
		{
			ushort blockIndex = blockEntityIndexFromBlockId(block.id);
			BlockEntityData entity = clientWorld.entityAccess.getBlockEntity(cwp, blockIndex);

			if (entity.type == BlockEntityType.localBlockEntity)
			{
				ushort targetEntityId = blockEntityManager.getId(entityName);
				return entity.id == targetEntityId;
			}
		}
		return false;
	}
}

// (1) x² + y² = R²
// (2) x = t(x₁-x₂) + x₂
// (3) y = t(y₁-y₂) + y₂
// We substitute (2) and (3) into (1) and get quadratic equation
// t²((x₁-x₂)² + (y₁-y₂)²) + t2((y₁-y₂)y₂ + (x₁-x₂)x₂) + x₂ + y₂ - R² = 0
// solve for t

// a = (x1 - x2)^2 + (y1 - y2)^2;
// b = 2 * ((y1-y2)*y2 + (x1-x2)*x2);
// c = x^2 + y^2 - R^2;
// d = b*b - 4*a*c;
