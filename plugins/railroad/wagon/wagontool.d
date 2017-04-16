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
