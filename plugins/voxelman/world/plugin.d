/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.plugin;

import std.experimental.logger;
import std.concurrency;
import netlib;
import pluginlib;

import voxelman.core.config;
import voxelman.core.events;
import voxelman.net.events;
import voxelman.utils.compression;

import voxelman.input.keybindingmanager;
import voxelman.config.configmanager : ConfigOption, ConfigManager;
import voxelman.eventdispatcher.plugin : EventDispatcherPlugin;
import voxelman.net.plugin : NetServerPlugin, NetClientPlugin;
import voxelman.login.plugin;
import voxelman.block.plugin;

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

import voxelman.world.worlddb;


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
	Tid ioThreadId;

public:
	this(void delegate(string) onPostInit)
	{
		this.onPostInit = onPostInit;
	}

	override string id() @property { return "voxelman.world.iomanager"; }

	override void preInit() {}
	override void init(IResourceManagerRegistry resmanRegistry) {
		ConfigManager config = resmanRegistry.getResourceManager!ConfigManager;
		saveDirOpt = config.registerOption!string("save_dir", "../../saves");
		worldNameOpt = config.registerOption!string("world_name", "world");
	}
	override void loadResources() {}
	override void postInit() {
		import std.path : buildPath;
		auto saveFilename = buildPath(saveDirOpt.get!string, worldNameOpt.get!string~".db");
		onPostInit(saveFilename);
	}

	void registerWorldLoadHandler(IoHandler worldLoadHandler)
	{
		worldLoadHandlers ~= worldLoadHandler;
	}
}

/*
private void ioThread(string worldFilename)
{
	WorldDb worldDb = new WorldDb;
	worldDb.openWorld(worldFilename);
	scope (exit) worldDb.close();

	bool isRunning = true;
	try while (isRunning)
	{
		receive(
			(immutable IoHandler h)
			{
				h(worldDb);
			},
			(Variant v){isRunning = false;}
		);
	}
	catch(Throwable t)
	{
		error(t.to!string, " in io thread");
		throw t;
	}
}*/

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
	BlockPlugin blockPlugin;

	IoManager ioManager;
	Tid ioThreadId;

	ConfigOption numWorkersOpt;

	ubyte[] buf;
	WorldInfo worldInfo;

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
		numWorkersOpt = config.registerOption!uint("num_workers", 4);
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

		chunkProvider.init(ioThreadId, numWorkersOpt.get!uint);
	}

	override void init(IPluginManager pluginman)
	{
		blockPlugin = pluginman.getPlugin!BlockPlugin;
		clientDb = pluginman.getPlugin!ClientDbServer;
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&handlePreUpdateEvent);
		evDispatcher.subscribeToEvent(&handlePostUpdateEvent);
		evDispatcher.subscribeToEvent(&handleStopEvent);
		evDispatcher.subscribeToEvent(&handleClientDisconnected);

		import voxelman.core.packets : PlaceBlockPacket;
		connection = pluginman.getPlugin!NetServerPlugin;
		connection.registerPacketHandler!PlaceBlockPacket(&handlePlaceBlockPacket);
	}

	override void postInit() {}

	void sendTask(IoHandler handler)
	{
		ioThreadId.send(cast(immutable)&handler);
	}

	TimestampType currentTimestamp() @property
	{
		return worldInfo.simulationTick;
	}

	void save()
	{

	}

	private void handleIoManagerPostInit(string worldFilename)
	{
		WorldDb worldDb = new WorldDb;
		worldDb.openWorld(worldFilename);
		foreach(h; ioManager.worldLoadHandlers)
		{
			h(worldDb);
		}
		ioThreadId = spawn(&storageWorkerThread, thisTid, cast(immutable)worldDb);
	}

	private void readWorldInfo(WorldDb worldDb)
	{
		//ubyte[] data = cast(ubyte[])readFile(worldInfoFilename, 1024);
		//worldInfo = decodeCborSingleDup!WorldInfo(data);
	}

	private void writeWorldInfo()
	{
		//ubyte[] bufferTemp = buf;
		//size_t size = encodeCbor(bufferTemp[], worldInfo);
		//writeFile(worldInfoFilename, bufferTemp[0..size]);
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
