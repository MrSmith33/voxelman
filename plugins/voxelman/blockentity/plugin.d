module voxelman.blockentity.plugin;

import std.array : Appender;
import pluginlib;

import derelict.imgui.imgui;
import voxelman.utils.textformatter;
import voxelman.utils.mapping;

import voxelman.block.utils;
import voxelman.core.config;
import voxelman.core.events;
import voxelman.world.storage.blockentityaccess;
import voxelman.world.storage.coordinates;

import voxelman.block.plugin;
import voxelman.eventdispatcher.plugin;
import voxelman.world.clientworld;
import voxelman.worldinteraction.plugin;

shared static this()
{
	pluginRegistry.regClientPlugin(new BlockEntityClient);
	pluginRegistry.regServerPlugin(new BlockEntityServer);
}

final class BlockEntityClient : IPlugin {
	mixin IdAndSemverFrom!(voxelman.blockentity.plugininfo);
	override void registerResourceManagers(void delegate(IResourceManager) reg) {
		reg(new BlockEntityManager);
	}
	ClientWorld clientWorld;
	WorldInteractionPlugin worldInteraction;
	BlockPluginClient blockPlugin;

	override void init(IPluginManager pluginman)
	{
		clientWorld = pluginman.getPlugin!ClientWorld;
		worldInteraction = pluginman.getPlugin!WorldInteractionPlugin;
		blockPlugin = pluginman.getPlugin!BlockPluginClient;

		EventDispatcherPlugin evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onUpdateEvent);
	}

	void onUpdateEvent(ref UpdateEvent event)
	{
		auto blockId = worldInteraction.pickBlock();
		auto cwp = ChunkWorldPos(worldInteraction.blockPos);
		igBegin("Debug");
		if (isBlockEntity(blockId)) {
			BlockEntityData entity = clientWorld.entityAccess.getBlockEntity(cwp, blockId);
			with(BlockEntityType) final switch(entity.type)
			{
				case localBlockEntity:
					igTextf("Entity: @%s: id %s, data %s", blockId, entity.id, entity.entityData); break;
				case foreignBlockEntity:
					igTextf("Entity: @%s: foreign %s", blockId, entity.payload); break;
				case componentId:
					igTextf("Entity: @%s: entity id %s", blockId, entity.payload); break;
			}
		} else {
			igTextf("Block: %s", blockPlugin.getBlocks()[blockId].name);
		}
		igEnd();
	}
}

final class BlockEntityServer : IPlugin {
	mixin IdAndSemverFrom!(voxelman.blockentity.plugininfo);
	override void registerResourceManagers(void delegate(IResourceManager) reg) {
		reg(new BlockEntityManager);
	}
}

alias BlockEntityMeshhandler = void function(
	ref Appender!(ubyte[]) output,
	BlockEntityData data,
	ubyte[3] color, ubyte bx, ubyte by, ubyte bz,
	ubyte sides);

alias SolidityHandler = Solidity function(Side side);

struct BlockEntityInfo
{
	string name;
	BlockEntityMeshhandler meshHandler;
	SolidityHandler sideSolidity;
	ubyte[3] color;
	//bool isVisible = true;
	size_t id;
}

struct BlockEntityInfoSetter
{
	private Mapping!(BlockEntityInfo)* mapping;
	private size_t blockId;
	private ref BlockEntityInfo info() {return (*mapping)[blockId]; }

	ref BlockEntityInfoSetter meshHandler(BlockEntityMeshhandler val) { info.meshHandler = val; return this; }
	ref BlockEntityInfoSetter color(ubyte[3] color ...) { info.color = color; return this; }
	ref BlockEntityInfoSetter colorHex(uint hex) { info.color = [(hex>>16)&0xFF,(hex>>8)&0xFF,hex&0xFF]; return this; }
	//ref BlockEntityInfoSetter isVisible(bool val) { info.isVisible = val; return this; }
	ref BlockEntityInfoSetter sideSolidity(SolidityHandler val) { info.sideSolidity = val; return this; }
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
}
