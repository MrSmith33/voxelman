/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.blockentity.plugin;

import std.experimental.logger;

import pluginlib;

import derelict.imgui.imgui;
import voxelman.utils.textformatter;
import voxelman.utils.mapping;

import voxelman.block.utils;
import voxelman.core.config;
import voxelman.core.events;
import voxelman.core.packets;
import voxelman.blockentity.blockentityaccess;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.volume;

import voxelman.block.plugin;
import voxelman.edit.plugin;
import voxelman.eventdispatcher.plugin;
import voxelman.graphics.plugin;
import voxelman.net.plugin;
import voxelman.world.clientworld;
import voxelman.worldinteraction.plugin;

public import voxelman.blockentity.utils;

final class BlockEntityClient : IPlugin {
	mixin IdAndSemverFrom!(voxelman.blockentity.plugininfo);
	mixin BlockEntityCommon;

	private ClientWorld clientWorld;
	private WorldInteractionPlugin worldInteraction;
	private BlockPluginClient blockPlugin;
	private GraphicsPlugin graphics;
	private NetClientPlugin connection;

	override void init(IPluginManager pluginman)
	{
		clientWorld = pluginman.getPlugin!ClientWorld;
		worldInteraction = pluginman.getPlugin!WorldInteractionPlugin;
		blockPlugin = pluginman.getPlugin!BlockPluginClient;
		graphics = pluginman.getPlugin!GraphicsPlugin;

		EventDispatcherPlugin evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onUpdateEvent);

		connection = pluginman.getPlugin!NetClientPlugin;

		auto removeEntityTool = new class ITool
		{
			this() { name = "test.blockentity.block_entity"; }
			override void onUpdate()
			{

			}

			// remove
			override void onMainActionRelease() {
				auto blockId = worldInteraction.pickBlock();
				if (isBlockEntity(blockId)) {
					connection.send(RemoveBlockEntityPacket(worldInteraction.blockPos.vector.arrayof));
				}
			}

			// place
			override void onSecondaryActionRelease() {
				// TODO multi chunk block entity
			}
		};

		auto editPlugin = pluginman.getPlugin!EditPlugin;
		//editPlugin.registerTool(removeEntityTool);
	}

	void onUpdateEvent(ref UpdateEvent event)
	{
		auto blockId = worldInteraction.pickBlock();
		auto cwp = ChunkWorldPos(worldInteraction.blockPos);
		igBegin("Debug");
		if (isBlockEntity(blockId))
		{
			ushort blockIndex = blockIndexFromBlockId(blockId);
			BlockEntityData entity = clientWorld.entityAccess.getBlockEntity(cwp, blockIndex);
			auto entityBwp = BlockWorldPos(cwp, blockIndex);
			with(BlockEntityType) final switch(entity.type)
			{
				case localBlockEntity:
					BlockEntityInfo eInfo = blockEntityInfos[entity.id];
					Volume eVol = eInfo.boxHandler(entityBwp, entity);

					igTextf("Entity: @%s: id %s %s, data %s, size %s",
						blockIndex, entity.id, eInfo.name, entity.entityData, eVol.size);
					igTextf(" vol %s, pos %s", eVol, entityBwp);

					voxelman.world.storage.volume.putCube(graphics.debugBatch, eVol, Colors.red, false);
					break;
				case foreignBlockEntity:
					igTextf("Entity: @%s: foreign %s", blockIndex, entity.payload); break;
				case componentId:
					igTextf("Entity: @%s: entity id %s", blockIndex, entity.payload); break;
			}
		}
		else
		{
			igTextf("Block: %s %s", blockId, blockPlugin.getBlocks()[blockId].name);
		}
		igEnd();
	}
}

final class BlockEntityServer : IPlugin {
	mixin IdAndSemverFrom!(voxelman.blockentity.plugininfo);
	mixin BlockEntityCommon;
}

mixin template BlockEntityCommon()
{
	override void registerResourceManagers(void delegate(IResourceManager) reg) {
		blockEntityMan = new BlockEntityManager;
		reg(blockEntityMan);
	}
	BlockEntityManager blockEntityMan;

	BlockEntityInfoTable blockEntityInfos() {
		return BlockEntityInfoTable(cast(immutable)blockEntityMan.blockEntityMapping.infoArray);
	}
}

struct BlockEntityInfoSetter
{
	private Mapping!(BlockEntityInfo)* mapping;
	private size_t blockId;
	private ref BlockEntityInfo info() {return (*mapping)[blockId]; }

	ref BlockEntityInfoSetter color(ubyte[3] color ...) { info.color = color; return this; }
	ref BlockEntityInfoSetter colorHex(uint hex) { info.color = [(hex>>16)&0xFF,(hex>>8)&0xFF,hex&0xFF]; return this; }
	//ref BlockEntityInfoSetter isVisible(bool val) { info.isVisible = val; return this; }
	ref BlockEntityInfoSetter meshHandler(BlockEntityMeshhandler val) { info.meshHandler = val; return this; }
	ref BlockEntityInfoSetter sideSolidity(SolidityHandler val) { info.sideSolidity = val; return this; }
	ref BlockEntityInfoSetter boxHandler(EntityBoxHandler val) { info.boxHandler = val; return this; }
}

final class BlockEntityManager : IResourceManager
{
private:
	Mapping!BlockEntityInfo blockEntityMapping;

public:
	override string id() @property { return "voxelman.blockentity.blockentitymanager"; }

	BlockEntityInfoSetter regBlockEntity(string name) {
		size_t id = blockEntityMapping.put(BlockEntityInfo(name));
		assert(id <= ushort.max);
		return BlockEntityInfoSetter(&blockEntityMapping, id);
	}

	ushort getId(string name) {
		return cast(ushort)blockEntityMapping.id(name);
	}
}
