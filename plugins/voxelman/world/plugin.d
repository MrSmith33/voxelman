/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.plugin;

import netlib;
import pluginlib;

import voxelman.core.config : BlockId;
import voxelman.core.events : PreUpdateEvent, PostUpdateEvent, GameStopEvent;
import voxelman.block.blockman;

import voxelman.config.configmanager : ConfigOption, ConfigManager;
import voxelman.eventdispatcher.plugin : EventDispatcherPlugin;
import voxelman.net.plugin : NetServerPlugin;

import voxelman.storage.chunk;
import voxelman.storage.chunkmanager;
import voxelman.storage.chunkobservermanager;
import voxelman.storage.chunkprovider;
import voxelman.storage.chunkstorage;
import voxelman.storage.coordinates;
import voxelman.storage.volume;
import voxelman.storage.world;

shared static this()
{
	//pluginRegistry.regClientPlugin(new ClientWorld);
	pluginRegistry.regServerPlugin(new ServerWorld);
}

final class WorldAccess {
	private ChunkManager* chunkManager;

	this(ChunkManager* chunkManager) {
		this.chunkManager = chunkManager;
	}

	bool setBlock(BlockWorldPos bwp, BlockId blockId) {
		auto blockIndex = BlockChunkIndex(bwp);
		auto chunkPos = ChunkWorldPos(bwp);
		BlockId[] blocks = chunkManager.getWriteBuffer(chunkPos);
		if (blocks is null)
			return false;
		blocks[blockIndex] = blockId;

		import std.range : only;
		chunkManager.onBlockChanges(chunkPos, only(BlockChange(blockIndex.index, blockId)));
		return true;
	}

	BlockId getBlock(BlockWorldPos bwp) {
		auto blockIndex = BlockChunkIndex(bwp);
		auto chunkPos = ChunkWorldPos(bwp);
		auto snap = chunkManager.getChunkSnapshot(chunkPos);
		if (!snap.isNull) {
			return snap.blockData.getBlockType(blockIndex);
		}
		return 0;
	}

	bool isFree(BlockWorldPos bwp) {
		 return getBlock(bwp) < 2; // air or unknown
	}
}

final class ServerWorld : IPlugin
{
private:
	EventDispatcherPlugin evDispatcher;
	NetServerPlugin connection;

	ConfigOption saveDirOpt;
	ConfigOption worldNameOpt;
	ConfigOption numWorkersOpt;

public:
	ChunkManager chunkManager;
	ChunkProvider chunkProvider;
	ChunkObserverManager chunkObserverManager;

	World world;
	WorldAccess worldAccess;
	BlockMan blockMan;

	mixin IdAndSemverFrom!(voxelman.world.plugininfo);

	override void registerResourceManagers(void delegate(IResourceManager) registerHandler) {}

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		ConfigManager config = resmanRegistry.getResourceManager!ConfigManager;
		saveDirOpt = config.registerOption!string("save_dir", "../../saves");
		worldNameOpt = config.registerOption!string("world_name", "world");
		numWorkersOpt = config.registerOption!uint("num_workers", 4);
	}

	override void preInit()
	{
		chunkManager = new ChunkManager();
		worldAccess = new WorldAccess(&chunkManager);
		chunkObserverManager = new ChunkObserverManager();

		// Component connections
		chunkManager.loadChunkHandler = &chunkProvider.loadChunk;
		chunkManager.saveChunkHandler = &chunkProvider.saveChunk;

		chunkProvider.onChunkLoadedHandlers ~= &chunkManager.onSnapshotLoaded;
		chunkProvider.onChunkSavedHandlers ~= &chunkManager.onSnapshotSaved;

		chunkObserverManager.changeChunkNumObservers = &chunkManager.setExternalChunkUsers;
		chunkObserverManager.chunkObserverAdded = &onChunkObserverAdded;
		chunkObserverManager.loadQueueSpaceAvaliable = &chunkProvider.loadQueueSpaceAvaliable;

		chunkManager.onChunkLoadedHandlers ~= &onChunkLoaded;
		chunkManager.chunkChangesHandlers ~= &sendChanges;

		blockMan.loadBlockTypes();
		auto worldDir = saveDirOpt.get!string ~ "/" ~ worldNameOpt.get!string;
		chunkProvider.init(worldDir, numWorkersOpt.get!uint);
		world.init(worldDir);
		world.load();
	}

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&handlePreUpdateEvent);
		evDispatcher.subscribeToEvent(&handlePostUpdateEvent);
		evDispatcher.subscribeToEvent(&handleStopEvent);

		import voxelman.core.packets : PlaceBlockPacket;
		connection = pluginman.getPlugin!NetServerPlugin;
		connection.registerPacketHandler!PlaceBlockPacket(&handlePlaceBlockPacket);
	}

	override void postInit() {}

	void handlePreUpdateEvent(ref PreUpdateEvent event)
	{
		chunkProvider.update();
		chunkObserverManager.update();
		world.update();
	}

	void handlePostUpdateEvent(ref PostUpdateEvent event)
	{
		chunkManager.commitSnapshots(world.currentTimestamp);
		chunkManager.sendChanges();
	}

	void handleStopEvent(ref GameStopEvent event)
	{
		chunkProvider.stop();
		world.save();
	}

	void onChunkObserverAdded(ChunkWorldPos cwp, ClientId clientId)
	{
		import voxelman.core.packets : ChunkDataPacket;
		auto snap = chunkManager.getChunkSnapshot(cwp);
		if (!snap.isNull) {
			connection.sendTo(clientId, ChunkDataPacket(cwp.vector, snap.blockData));
		}
	}

	void onChunkLoaded(ChunkWorldPos cwp, BlockDataSnapshot snap)
	{
		import voxelman.core.packets : ChunkDataPacket;
		connection.sendTo(
			chunkObserverManager.getChunkObservers(cwp),
			ChunkDataPacket(cwp.vector, snap.blockData));
	}

	void sendChanges(BlockChange[][ChunkWorldPos] changes)
	{
		import voxelman.core.packets : MultiblockChangePacket;
		foreach(pair; changes.byKeyValue)
		{
			connection.sendTo(
				chunkObserverManager.getChunkObservers(pair.key),
				MultiblockChangePacket(pair.key.vector, pair.value));
		}
	}

	void handlePlaceBlockPacket(ubyte[] packetData, ClientId clientId)
	{
		import voxelman.core.packets : PlaceBlockPacket;
		//if (serverPlugin.isLoggedIn(clientId))
		{
			auto packet = unpackPacket!PlaceBlockPacket(packetData);
			worldAccess.setBlock(BlockWorldPos(packet.blockPos), packet.blockId);
		}
	}
}
