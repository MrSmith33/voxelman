/**
Copyright: Copyright (c) 2016-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.blockentity.plugin;

import voxelman.log;

import pluginlib;
import voxelman.container.buffer;
import voxelman.math;

import voxelman.text.textformatter;

import voxelman.world.block;
import voxelman.core.config;
import voxelman.core.events;
import voxelman.core.packets;
import voxelman.world.storage;

import voxelman.block.plugin;
import voxelman.edit.plugin;
import voxelman.dbg.plugin;
import voxelman.graphics.plugin;
import voxelman.net.plugin;
import voxelman.world.clientworld;
import voxelman.world.serverworld;
import voxelman.worldinteraction.plugin;

import voxelman.edit.tools.itool;
import voxelman.blockentity.blockentityman;
import voxelman.world.blockentity;

final class BlockEntityClient : IPlugin {
	mixin IdAndSemverFrom!"voxelman.blockentity.plugininfo";
	mixin BlockEntityCommon;

	private ClientWorld clientWorld;
	private WorldInteractionPlugin worldInteraction;
	private BlockPluginClient blockPlugin;
	private GraphicsPlugin graphics;
	private NetClientPlugin connection;

	bool blockEntityDebug = false;

	override void init(IPluginManager pluginman)
	{
		clientWorld = pluginman.getPlugin!ClientWorld;
		worldInteraction = pluginman.getPlugin!WorldInteractionPlugin;
		blockPlugin = pluginman.getPlugin!BlockPluginClient;
		graphics = pluginman.getPlugin!GraphicsPlugin;

		connection = pluginman.getPlugin!NetClientPlugin;

		auto debugClient = pluginman.getPlugin!DebugClient;
		debugClient.registerDebugGuiHandler(&showBlockInfo, INFO_ORDER - 2, "BlockInfo");

		auto entityTool = new class ITool
		{
			this() { name = "test.blockentity.block_entity"; }

			bool placing;
			WorldBox selection;
			BlockWorldPos startingPos;

			override void onUpdate() {
				auto cursor = worldInteraction.sideBlockPos;
				selection = worldBoxFromCorners(startingPos.xyz,
					cursor.xyz, cast(DimensionId)cursor.w);
				drawSelection();
			}

			// remove
			override void onMainActionRelease() {
				if (placing) return;
				auto block = worldInteraction.pickBlock();
				if (isBlockEntity(block.id)) {
					connection.send(RemoveBlockEntityPacket(worldInteraction.blockPos.vector));
				}
			}

			// place
			override void onSecondaryActionPress() {
				placing = true;
				startingPos = worldInteraction.sideBlockPos;
			}
			override void onSecondaryActionRelease() {
				if (placing) {
					ulong sizeData = sizeToEntityData(selection.size);
					ulong payload = payloadFromIdAndEntityData(
						blockEntityMan.getId("multi"), sizeData);
					connection.send(PlaceBlockEntityPacket(selection, payload));
					placing = false;
				}
			}

			void drawSelection() {
				if (placing) {
					graphics.debugBatch.putCube(vec3(selection.position) - cursorOffset,
						vec3(selection.size) + cursorOffset, Colors.blue, false);
				} else {
					worldInteraction.drawCursor(worldInteraction.sideBlockPos, Colors.blue);
				}
			}
		};

		auto editPlugin = pluginman.getPlugin!EditPlugin;
		editPlugin.registerTool(entityTool);
	}

	void showBlockInfo()
	{
		auto block = worldInteraction.pickBlock();
		auto bwp = worldInteraction.blockPos;
		auto cwp = ChunkWorldPos(bwp);

		if (isBlockEntity(block.id))
		{
			ushort blockIndex = blockEntityIndexFromBlockId(block.id);
			BlockEntityData entity = clientWorld.entityAccess.getBlockEntity(cwp, blockIndex);
			with(BlockEntityType) final switch(entity.type)
			{
				case localBlockEntity:
					BlockEntityInfo eInfo = blockEntityInfos[entity.id];
					auto entityBwp = BlockWorldPos(cwp, blockIndex);
					WorldBox eVol = eInfo.boxHandler(entityBwp, entity);

					//igTextf("Entity(main): id %s %s ind %s %s",
					//	entity.id, eInfo.name, blockIndex, eVol);

					//igCheckbox("Debug entity", &blockEntityDebug);
					if (blockEntityDebug && eInfo.debugHandler)
					{
						auto context = BlockEntityDebugContext(entityBwp, entity, graphics);
						eInfo.debugHandler(context);
					}

					putCube(graphics.debugBatch, eVol, Colors.red, false);
					break;
				case foreignBlockEntity:
					auto mainPtr = entity.mainChunkPointer;

					auto mainCwp = ChunkWorldPos(ivec3(cwp.xyz) - mainPtr.mainChunkOffset, cwp.w);
					BlockEntityData mainEntity = clientWorld.entityAccess.getBlockEntity(mainCwp, mainPtr.blockIndex);
					auto mainBwp = BlockWorldPos(mainCwp, mainPtr.blockIndex);

					BlockEntityInfo eInfo = blockEntityInfos[mainPtr.entityId];
					WorldBox eVol = eInfo.boxHandler(mainBwp, mainEntity);

					//igTextf("Entity(other): ind %s mid %s mind %s moff %s",
					//	blockIndex, mainPtr.entityId,
					//	mainPtr.blockIndex, mainPtr.mainChunkOffset);
					//igTextf(" %s %s", eInfo.name, eVol);

					putCube(graphics.debugBatch, eVol, Colors.red, false);
					break;
				//case componentId:
				//	igTextf("Entity: @%s: entity id %s", blockIndex, entity.payload); break;
			}
		}
		else
		{
			auto binfo = blockPlugin.getBlocks()[block.id];
			//igTextf("Block: %s:%s %s", block.id, block.metadata, binfo.name);
			//igTextf(" @ %s %s %s", bwp, cwp, BlockChunkPos(bwp));
		}
	}
}

final class BlockEntityServer : IPlugin {
	mixin IdAndSemverFrom!"voxelman.blockentity.plugininfo";
	mixin BlockEntityCommon;
	auto dbKey = IoKey("voxelman.blockentity.plugin");

	override void registerResources(IResourceManagerRegistry resmanRegistry) {
		auto ioman = resmanRegistry.getResourceManager!IoManager;
		ioman.registerWorldLoadSaveHandlers(&read, &write);
	}

	void read(ref PluginDataLoader loader) {
		loader.readMapping(dbKey, blockEntityMan.blockEntityMapping);
	}

	void write(ref PluginDataSaver saver) {
		saver.writeMapping(dbKey, blockEntityMan.blockEntityMapping);
	}
}

mixin template BlockEntityCommon()
{
	override void registerResourceManagers(void delegate(IResourceManager) reg) {
		blockEntityMan = new BlockEntityManager;
		blockEntityMan.regBlockEntity("unknown") // 0
			.boxHandler(&nullBoxHandler);
		blockEntityMan.regBlockEntity("multi")
			.boxHandler(&multichunkBoxHandler)
			.meshHandler(&multichunkMeshHandler)
			.blockShapeHandler(&multichunkBlockShapeHandler);
			//.debugHandler(&multichunkDebugHandler);
		reg(blockEntityMan);
	}
	BlockEntityManager blockEntityMan;

	BlockEntityInfoTable blockEntityInfos() {
		return BlockEntityInfoTable(cast(immutable)blockEntityMan.blockEntityMapping.infoArray);
	}
}

void multichunkMeshHandler(BlockEntityMeshingData meshingData)
{
	static ubvec3 mainColor = ubvec3(60,0,0);
	static ubvec3 otherColor = ubvec3(0,0,60);

	ubvec3 col;
	if (meshingData.data.type == BlockEntityType.localBlockEntity)
		col = mainColor;
	else
		col = otherColor;

	auto blockMeshingData = BlockMeshingData(
				&meshingData.output[Solidity.solid],
				meshingData.occlusionHandler,
				col,
				[0,0],
				ubvec3(meshingData.chunkPos),
				meshingData.sides,
				meshingData.blockIndex);
	import voxelman.world.mesh.blockmeshers.full : makeColoredFullBlockMesh;
	makeColoredFullBlockMesh(blockMeshingData);
}

WorldBox multichunkBoxHandler(BlockWorldPos bwp, BlockEntityData data)
{
	ulong sizeData = data.entityData;
	ivec3 size = entityDataToSize(sizeData);
	return WorldBox(bwp.xyz, size, cast(ushort)bwp.w);
}

void multichunkDebugHandler(ref BlockEntityDebugContext context)
{
	ulong sizeData = context.data.entityData;
	ivec3 size = entityDataToSize(sizeData);
	//auto vol = WorldBox(bwp.xyz, size, cast(ushort)bwp.w);
}

BlockShape multichunkBlockShapeHandler(ivec3, ivec3, BlockEntityData) {
	return fullShape;
}
