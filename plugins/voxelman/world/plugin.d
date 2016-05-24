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

import voxelman.world.storage.chunk;
import voxelman.world.storage.chunkmanager;
import voxelman.world.storage.chunkobservermanager;
import voxelman.world.storage.chunkprovider;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.storageworker;
import voxelman.world.storage.volume;
import voxelman.world.storage.worldaccess;

public import voxelman.world.worlddb : WorldDb;


alias IoHandler = void delegate(WorldDb);

final class IoManager : IResourceManager
{
private:
	ConfigOption saveDirOpt;
	ConfigOption worldNameOpt;
	void delegate(string) onPostInit;

	IoHandler[] worldLoadHandlers;
	IoHandler[] worldSaveHandlers;

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
}

//version = DBG_COMPR;
final class ServerWorld : IPlugin
{
private:
	EventDispatcherPlugin evDispatcher;
	NetServerPlugin connection;
	ClientDbServer clientDb;
	BlockPluginServer blockPlugin;

	IoManager ioManager;

	ConfigOption numGenWorkersOpt;

	ubyte[] buf;
	WorldInfo worldInfo;
	immutable string worldInfoKey = "voxelman.world.world_info";
	string worldFilename;

	shared bool isSaving;
	WorldDb worldDb;

public:
	ChunkManager chunkManager;
	ChunkChangeManager chunkChangeManager;
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
		chunkChangeManager = new ChunkChangeManager();
		worldAccess = new WorldAccess(chunkManager, chunkChangeManager);
		chunkObserverManager = new ChunkObserverManager();

		ubyte numLayers = 1;
		chunkManager.setup(numLayers);

		// Component connections
		chunkManager.startChunkSave = &chunkProvider.startChunkSave;
		chunkManager.loadChunkHandler = &chunkProvider.loadChunk;

		chunkProvider.onChunkLoadedHandler = &chunkManager.onSnapshotLoaded!LoadedChunkData;
		chunkProvider.onChunkSavedHandler = &chunkManager.onSnapshotSaved!SavedChunkData;

		chunkChangeManager.setup(numLayers);

		chunkObserverManager.changeChunkNumObservers = &chunkManager.setExternalChunkObservers;
		chunkObserverManager.chunkObserverAdded = &onChunkObserverAdded;
		chunkObserverManager.loadQueueSpaceAvaliable = &chunkProvider.loadQueueSpaceAvaliable;

		chunkManager.onChunkLoadedHandler = &onChunkLoaded;
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

		chunkProvider.init(worldDb, numGenWorkersOpt.get!uint, blockPlugin.getBlocks());
		worldDb = null;
	}

	void sendTask(IoHandler handler)
	{
		// TODO
		//ioThreadId.send(cast(immutable)handler);
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
		worldDb = new WorldDb;
		worldDb.open(_worldFilename);
		readWorldInfo(worldDb);
		foreach(h; ioManager.worldLoadHandlers)
			h(worldDb);
	}

	private void readWorldInfo(WorldDb worldDb)
	{
		import std.path : absolutePath, buildNormalizedPath;
		worldDb.beginTxn();
		ubyte[] data = worldDb.getPerWorldValue(worldInfoKey);
		scope(exit) worldDb.commitTxn();
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
		worldDb.putPerWorldValue(worldInfoKey, worldDb.tempBuffer[0..encodedSize]);
	}

	private void handlePreUpdateEvent(ref PreUpdateEvent event)
	{
		++worldInfo.simulationTick;
		chunkProvider.update();
		chunkObserverManager.update();
	}

	private void handlePostUpdateEvent(ref PostUpdateEvent event)
	{
		chunkManager.commitSnapshots(currentTimestamp);
		sendChanges(chunkChangeManager.chunkChanges[FIRST_LAYER]);
		chunkChangeManager.chunkChanges[FIRST_LAYER] = null;
	}

	private void handleStopEvent(ref GameStopEvent event)
	{
		chunkProvider.stop();
	}

	private void onChunkObserverAdded(ChunkWorldPos cwp, ClientId clientId)
	{
		auto snap = chunkManager.getChunkSnapshot(cwp, FIRST_LAYER); //TODO send other layers
		if (!snap.isNull) {
			sendChunk(clientId, cwp, snap);
		}
	}

	private void handleClientDisconnected(ref ClientDisconnectedEvent event)
	{
		chunkObserverManager.removeObserver(event.clientId);
	}

	private void onChunkLoaded(ChunkWorldPos cwp)
	{
		auto snap = chunkManager.getChunkSnapshot(cwp, FIRST_LAYER); //TODO send other layers
		if (!snap.isNull) {
			sendChunk(chunkObserverManager.getChunkObservers(cwp), cwp, snap);
		}
	}

	private void sendChunk(C)(C clients, ChunkWorldPos cwp, ChunkLayerSnap layer)
	{
		import voxelman.core.packets : ChunkDataPacket;
		version(DBG_COMPR)if (layer.type != StorageType.uniform)
		{
			ubyte[] compactBlocks = layer.getArray!ubyte;
			infof("Send %s %s %s\n(%(%02x%))", cwp, compactBlocks.ptr, compactBlocks.length, cast(ubyte[])compactBlocks);
		}
		BlockData bd = layer.toBlockData();
		if (layer.type == StorageType.fullArray)
		{
			ubyte[] compactBlocks = compress(cast(ubyte[])layer.getArray!BlockId, buf);
			bd.blocks = compactBlocks;
		}
		connection.sendTo(clients, ChunkDataPacket(cwp.ivector, bd));
	}

	private void sendChanges(BlockChange[][ChunkWorldPos] changes)
	{
		import voxelman.core.packets : MultiblockChangePacket;
		foreach(pair; changes.byKeyValue)
		{
			connection.sendTo(
				chunkObserverManager.getChunkObservers(pair.key),
				MultiblockChangePacket(pair.key.ivector, pair.value));
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
