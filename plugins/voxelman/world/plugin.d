/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.plugin;

import std.experimental.logger;
import std.concurrency : spawn, thisTid;
import std.array : empty;
import core.atomic : atomicStore, atomicLoad;
import cbor;
import netlib;
import pluginlib;

import voxelman.core.config;
import voxelman.core.events;
import voxelman.net.events;
import voxelman.utils.compression;

import voxelman.input.keybindingmanager;
import voxelman.config.configmanager : ConfigOption, ConfigManager;
import voxelman.eventdispatcher.plugin : EventDispatcherPlugin;
import voxelman.net.plugin : NetServerPlugin;
import voxelman.login.plugin;
import voxelman.block.plugin;
import voxelman.server.plugin : WorldSaveInternalEvent;

import voxelman.net.packets;
import voxelman.core.packets;

import voxelman.storage.chunk;
import voxelman.storage.chunkmanager;
import voxelman.storage.chunkobservermanager;
import voxelman.storage.chunkprovider;
import voxelman.storage.chunkstorage;
import voxelman.storage.coordinates;
import voxelman.storage.volume;
import voxelman.storage.storageworker;

public import voxelman.world.worlddb : WorldDb;


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


alias IoHandler = void delegate(WorldDb);

final class IoManager : IResourceManager
{
private:
	ConfigOption saveDirOpt;
	ConfigOption worldNameOpt;
	void delegate(string) onPostInit;

	IoHandler[] worldLoadHandlers;
	IoHandler[] worldSaveHandlers;
	Tid ioThreadId;

public:
	this(void delegate(string) onPostInit)
	{
		this.onPostInit = onPostInit;
	}

	override string id() @property { return "voxelman.world.iomanager"; }

	override void init(IResourceManagerRegistry resmanRegistry) {
		ConfigManager config = resmanRegistry.getResourceManager!ConfigManager;
		saveDirOpt = config.registerOption!string("save_dir", "../../saves");
		worldNameOpt = config.registerOption!string("world_name", "world");
	}
	override void postInit() {
		import std.path : buildPath;
		auto saveFilename = buildPath(saveDirOpt.get!string, worldNameOpt.get!string~".db");
		onPostInit(saveFilename);
	}

	void registerWorldLoadHandler(IoHandler worldLoadHandler)
	{
		worldLoadHandlers ~= worldLoadHandler;
	}

	void registerWorldSaveHandler(IoHandler worldSaveHandler)
	{
		worldSaveHandlers ~= worldSaveHandler;
	}
}

struct WorldInfo
{
	string name = DEFAULT_WORLD_NAME;
	TimestampType simulationTick;
	ivec3 spawnPosition;
	//block mapping
}

final class ServerWorld : IPlugin
{
private:
	EventDispatcherPlugin evDispatcher;
	NetServerPlugin connection;
	ClientDbServer clientDb;
	BlockPluginServer blockPlugin;

	IoManager ioManager;
	Tid ioThreadId;

	ConfigOption numGenWorkersOpt;

	ubyte[] buf;
	WorldInfo worldInfo;
	immutable string worldInfoKey = "voxelman.world.world_info";
	string worldFilename;

	shared bool isSaving;

public:
	ChunkManager chunkManager;
	ChunkProvider chunkProvider;
	ChunkObserverManager chunkObserverManager;

	WorldAccess worldAccess;

	mixin IdAndSemverFrom!(voxelman.world.plugininfo);

	override void registerResourceManagers(void delegate(IResourceManager) registerHandler)
	{
		ioManager = new IoManager(&handleIoManagerPostInit);
		registerHandler(ioManager);
	}

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		ConfigManager config = resmanRegistry.getResourceManager!ConfigManager;
		numGenWorkersOpt = config.registerOption!uint("num_workers", 4);
	}

	override void preInit()
	{
		buf = new ubyte[](1024*64);
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

		chunkProvider.init(ioThreadId, numGenWorkersOpt.get!uint);
	}

	override void init(IPluginManager pluginman)
	{
		blockPlugin = pluginman.getPlugin!BlockPluginServer;
		clientDb = pluginman.getPlugin!ClientDbServer;
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&handlePreUpdateEvent);
		evDispatcher.subscribeToEvent(&handlePostUpdateEvent);
		evDispatcher.subscribeToEvent(&handleStopEvent);
		evDispatcher.subscribeToEvent(&handleClientDisconnected);
		evDispatcher.subscribeToEvent(&handleSaveEvent);

		import voxelman.core.packets : PlaceBlockPacket;
		connection = pluginman.getPlugin!NetServerPlugin;
		connection.registerPacketHandler!PlaceBlockPacket(&handlePlaceBlockPacket);
	}

	void sendTask(IoHandler handler)
	{
		ioThreadId.send(cast(immutable)handler);
	}

	TimestampType currentTimestamp() @property
	{
		return worldInfo.simulationTick;
	}

	private void handleSaveEvent(ref WorldSaveInternalEvent event)
	{
		if (!atomicLoad(isSaving)) {
			atomicStore(isSaving, true);
			chunkManager.save();
			foreach(h; ioManager.worldSaveHandlers)
				sendTask(h);
			evDispatcher.postEvent(WorldSaveEvent());
			sendTask(&handleSaveEndTask);
		}
	}

	private void handleSaveEndTask(WorldDb)
	{
		atomicStore(isSaving, false);
	}

	// Load world
	private void handleIoManagerPostInit(string _worldFilename)
	{
		worldFilename = _worldFilename;
		WorldDb worldDb = new WorldDb;
		worldDb.openWorld(_worldFilename);
		readWorldInfo(worldDb);
		foreach(h; ioManager.worldLoadHandlers)
			h(worldDb);
		ioThreadId = spawn(&storageWorkerThread, thisTid, cast(immutable)worldDb);
	}

	private void readWorldInfo(WorldDb worldDb)
	{
		import std.path : absolutePath, buildNormalizedPath;
		ubyte[] data = worldDb.loadPerWorldData(worldInfoKey);
		scope(exit) worldDb.perWorldSelectStmt.reset();
		if (!data.empty) {
			worldInfo = decodeCborSingleDup!WorldInfo(data);
			infof("Loading world %s", worldFilename.absolutePath.buildNormalizedPath);
		}
		else
			writeWorldInfo(worldDb);
	}

	private void writeWorldInfo(WorldDb worldDb)
	{
		size_t encodedSize = encodeCborArray(worldDb.tempBuffer, worldInfo);
		worldDb.savePerWorldData(worldInfoKey, worldDb.tempBuffer[0..encodedSize]);
	}

	private void handlePreUpdateEvent(ref PreUpdateEvent event)
	{
		chunkProvider.update();
		chunkObserverManager.update();
		++worldInfo.simulationTick;
	}

	private void handlePostUpdateEvent(ref PostUpdateEvent event)
	{
		chunkManager.commitSnapshots(currentTimestamp);
		chunkManager.sendChanges();
	}

	private void handleStopEvent(ref GameStopEvent event)
	{
		ioThreadId.send(0);
		chunkProvider.stop();
	}

	private void onChunkObserverAdded(ChunkWorldPos cwp, ClientId clientId)
	{
		auto snap = chunkManager.getChunkSnapshot(cwp);
		if (!snap.isNull) {
			sendChunk(clientId, cwp, snap.blockData);
		}
	}

	private void handleClientDisconnected(ref ClientDisconnectedEvent event)
	{
		chunkObserverManager.removeObserver(event.clientId);
	}

	private void onChunkLoaded(ChunkWorldPos cwp, BlockDataSnapshot snap)
	{
		sendChunk(chunkObserverManager.getChunkObservers(cwp), cwp, snap.blockData);
	}

	private void sendChunk(C)(C clients, ChunkWorldPos cwp, BlockData bd)
	{
		import voxelman.core.packets : ChunkDataPacket;
		import voxelman.utils.compression;
		bd.validate();
		if (!bd.uniform) bd.blocks = compress(bd.blocks, buf);
		connection.sendTo(clients, ChunkDataPacket(cwp.vector, bd));
	}

	private void sendChanges(BlockChange[][ChunkWorldPos] changes)
	{
		import voxelman.core.packets : MultiblockChangePacket;
		foreach(pair; changes.byKeyValue)
		{
			connection.sendTo(
				chunkObserverManager.getChunkObservers(pair.key),
				MultiblockChangePacket(pair.key.vector, pair.value));
		}
	}

	private void handlePlaceBlockPacket(ubyte[] packetData, ClientId clientId)
	{
		import voxelman.core.packets : PlaceBlockPacket;
		if (clientDb.isSpawned(clientId))
		{
			auto packet = unpackPacket!PlaceBlockPacket(packetData);
			worldAccess.setBlock(BlockWorldPos(packet.blockPos), packet.blockId);
		}
	}
}
