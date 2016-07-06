/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.blockentity.plugin;

import std.experimental.logger;
import std.array : Appender;

import pluginlib;

import derelict.imgui.imgui;
import voxelman.utils.textformatter;
import voxelman.utils.mapping;

import voxelman.block.utils;
import voxelman.core.config;
import voxelman.core.events;
import voxelman.core.packets;
import voxelman.core.chunkmesh;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.worldbox;

import voxelman.block.plugin;
import voxelman.edit.plugin;
import voxelman.eventdispatcher.plugin;
import voxelman.graphics.plugin;
import voxelman.net.plugin;
import voxelman.world.clientworld;
import voxelman.worldinteraction.plugin;

public import voxelman.blockentity.blockentityaccess;
public import voxelman.blockentity.blockentitydata;
public import voxelman.blockentity.blockentitymap;
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

			bool placing;
			WorldBox selection;
			BlockWorldPos startingPos;

			override void onUpdate() {
				auto cursor = worldInteraction.sideBlockPos;
				selection = worldBoxFromCorners(startingPos.xyz,
					cursor.xyz, cast(DimentionId)cursor.w);
				drawSelection();
			}

			// remove
			override void onMainActionRelease() {
				if (placing) return;
				auto blockId = worldInteraction.pickBlock();
				if (isBlockEntity(blockId)) {
					connection.send(RemoveBlockEntityPacket(worldInteraction.blockPos.vector.arrayof));
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
					if (!worldInteraction.cameraInSolidBlock)
					{
						worldInteraction.drawCursor(worldInteraction.sideBlockPos, Colors.blue);
					}
				}
			}
		};

		auto editPlugin = pluginman.getPlugin!EditPlugin;
		editPlugin.registerTool(removeEntityTool);
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
			with(BlockEntityType) final switch(entity.type)
			{
				case localBlockEntity:
					BlockEntityInfo eInfo = blockEntityInfos[entity.id];
					auto entityBwp = BlockWorldPos(cwp, blockIndex);
					WorldBox eVol = eInfo.boxHandler(entityBwp, entity);

					igTextf("Entity(main): ind %s: id %s %s %s",
						blockIndex, entity.id, eInfo.name, eVol);
					if (eInfo.debugHandler)
						eInfo.debugHandler(entityBwp, entity);

					voxelman.world.storage.worldbox.putCube(graphics.debugBatch, eVol, Colors.red, false);
					break;
				case foreignBlockEntity:
					auto mainPtr = entity.mainChunkPointer;

					auto mainCwp = ChunkWorldPos(ivec3(cwp.xyz) - mainPtr.mainChunkOffset, cwp.w);
					BlockEntityData mainEntity = clientWorld.entityAccess.getBlockEntity(mainCwp, mainPtr.blockIndex);
					auto mainBwp = BlockWorldPos(mainCwp, mainPtr.blockIndex);

					BlockEntityInfo eInfo = blockEntityInfos[mainPtr.entityId];
					WorldBox eVol = eInfo.boxHandler(mainBwp, mainEntity);

					igTextf("Entity(other): ind %s mid %s mind %s moff %s",
						blockIndex, mainPtr.entityId,
						mainPtr.blockIndex, mainPtr.mainChunkOffset);
					igTextf(" %s %s", eInfo.name, eVol);

					voxelman.world.storage.worldbox.putCube(graphics.debugBatch, eVol, Colors.red, false);
					break;
				//case componentId:
				//	igTextf("Entity: @%s: entity id %s", blockIndex, entity.payload); break;
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
		blockEntityMan.regBlockEntity("unknown") // 0
			.boxHandler(&nullBoxHandler);
		blockEntityMan.regBlockEntity("multi")
			.boxHandler(&multichunkBoxHandler)
			.meshHandler(&multichunkMeshHandler);
			//.debugHandler(&multichunkDebugHandler);
		reg(blockEntityMan);
	}
	BlockEntityManager blockEntityMan;

	BlockEntityInfoTable blockEntityInfos() {
		return BlockEntityInfoTable(cast(immutable)blockEntityMan.blockEntityMapping.infoArray);
	}
}

void multichunkMeshHandler(
	Appender!(MeshVertex[])[] output,
	BlockEntityData data,
	ubyte[3] color,
	ubyte sides,
	//ivec3 worldPos,
	ivec3 chunkPos,
	ivec3 entityPos)
{
	static ubyte[3] mainColor = [60,0,0];
	static ubyte[3] otherColor = [0,0,60];

	ubyte[3] col;
	if (data.type == BlockEntityType.localBlockEntity)
		col = mainColor;
	else
		col = otherColor;

	makeColoredBlockMesh(output[Solidity.solid], col,
		cast(ubyte)chunkPos.x,
		cast(ubyte)chunkPos.y,
		cast(ubyte)chunkPos.z,
		sides);
}

WorldBox multichunkBoxHandler(BlockWorldPos bwp, BlockEntityData data)
{
	ulong sizeData = data.entityData;
	ivec3 size = entityDataToSize(sizeData);
	return WorldBox(bwp.xyz, size, cast(ushort)bwp.w);
}

void multichunkDebugHandler(BlockWorldPos bwp, BlockEntityData data)
{
	ulong sizeData = data.entityData;
	ivec3 size = entityDataToSize(sizeData);
	//auto vol = WorldBox(bwp.xyz, size, cast(ushort)bwp.w);
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
	ref BlockEntityInfoSetter debugHandler(EntityDebugHandler val) { info.debugHandler = val; return this; }
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
