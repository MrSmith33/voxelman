/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.plugin;

import std.experimental.logger;
import std.experimental.allocator.mallocator;
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
import voxelman.utils.hashset;

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


alias SaveHandler = void delegate(ref PluginDataSaver);
alias LoadHandler = void delegate(ref PluginDataLoader);

final class IoManager : IResourceManager
{
private:
	ConfigOption saveDirOpt;
	ConfigOption worldNameOpt;
	void delegate(string) onPostInit;

	LoadHandler[] worldLoadHandlers;
	SaveHandler[] worldSaveHandlers;

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
		import std.file : mkdirRecurse;
		auto saveFilename = buildPath(saveDirOpt.get!string, worldNameOpt.get!string~".db");
		mkdirRecurse(saveDirOpt.get!string);
		onPostInit(saveFilename);
	}

	void registerWorldLoadSaveHandlers(LoadHandler loadHandler, SaveHandler saveHandler)
	{
		worldLoadHandlers ~= loadHandler;
		worldSaveHandlers ~= saveHandler;
	}
}

struct PluginDataSaver
{
	enum DATA_BUF_SIZE = 1024*1024*2;
	enum KEY_BUF_SIZE = 1024*20;
	private ubyte[] dataBuf;
	private ubyte[] keyBuf;
	private size_t dataLen;
	private size_t keyLen;

	private void alloc() @nogc {
		dataBuf = cast(ubyte[])Mallocator.instance.allocate(DATA_BUF_SIZE);
		keyBuf = cast(ubyte[])Mallocator.instance.allocate(KEY_BUF_SIZE);
	}

	private void free() @nogc {
		Mallocator.instance.deallocate(dataBuf);
		Mallocator.instance.deallocate(keyBuf);
	}

	ubyte[] tempBuffer() @property @nogc {
		return dataBuf[dataLen..$];
	}

	void writeEntry(string key, size_t bytesWritten) {
		keyLen += encodeCbor(keyBuf[keyLen..$], key);
		keyLen += encodeCbor(keyBuf[keyLen..$], bytesWritten);
		dataLen += bytesWritten;
	}

	private void reset() @nogc {
		dataLen = 0;
		keyLen = 0;
	}

	private int opApply(int delegate(string key, ubyte[] data) dg)
	{
		ubyte[] keyEntriesData = keyBuf[0..keyLen];
		ubyte[] data = dataBuf;
		while(!keyEntriesData.empty)
		{
			auto key = decodeCborSingle!string(keyEntriesData);
			auto dataSize = decodeCborSingle!size_t(keyEntriesData);
			auto result = dg(key, data[0..dataSize]);
			data = data[dataSize..$];

			if (result) return result;
		}
		return 0;
	}
}

struct PluginDataLoader
{
	private WorldDb worldDb;

	ubyte[] readEntry(string key) {
		ubyte[] data = worldDb.getPerWorldValue(key);
		//infof("Reading %s %s", key, data.length);
		//printCborStream(data[]);
		return data;
	}
}

struct WorldInfo
{
	string name = DEFAULT_WORLD_NAME;
	TimestampType simulationTick;
	ivec3 spawnPosition;
}

struct ActiveChunks
{
	private immutable string dbKey = "voxelman.world.active_chunks";
	HashSet!ChunkWorldPos chunks;
	void delegate(ChunkWorldPos cwp) loadChunk;
	void delegate(ChunkWorldPos cwp) unloadChunk;

	void add(ChunkWorldPos cwp) {
		chunks.put(cwp);
		loadChunk(cwp);
	}

	void remove(ChunkWorldPos cwp) {
		if (chunks.remove(cwp))
			unloadChunk(cwp);
	}

	void loadActiveChunks() {
		foreach(cwp; chunks.items) {
			loadChunk(cwp);
			infof("load active: %s", cwp);
		}
	}

	private void read(ref PluginDataLoader loader) {
		ubyte[] data = loader.readEntry(dbKey);
		if (!data.empty) {
			auto token = decodeCborToken(data);
			assert(token.type == CborTokenType.arrayHeader);
			foreach(_; 0..token.uinteger)
				chunks.put(decodeCborSingle!ChunkWorldPos(data));
			assert(data.empty);
		}
	}

	private void write(ref PluginDataSaver saver) {
		auto sink = saver.tempBuffer;
		size_t encodedSize = encodeCborArrayHeader(sink[], chunks.length);
		foreach(cwp; chunks.items)
			encodedSize += encodeCbor(sink[encodedSize..$], cwp);
		saver.writeEntry(dbKey, encodedSize);
	}
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
	PluginDataSaver pluginDataSaver;

public:
	ChunkManager chunkManager;
	ChunkProvider chunkProvider;
	ChunkObserverManager chunkObserverManager;
	ActiveChunks activeChunks;

	WorldAccess worldAccess;

	mixin IdAndSemverFrom!(voxelman.world.plugininfo);

	override void registerResourceManagers(void delegate(IResourceManager) registerHandler)
	{
		ioManager = new IoManager(&loadWorld);
		registerHandler(ioManager);
	}

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		ConfigManager config = resmanRegistry.getResourceManager!ConfigManager;
		numGenWorkersOpt = config.registerOption!uint("num_workers", 4);
		ioManager.registerWorldLoadSaveHandlers(&readWorldInfo, &writeWorldInfo);
		ioManager.registerWorldLoadSaveHandlers(&activeChunks.read, &activeChunks.write);
	}

	override void preInit()
	{
		pluginDataSaver.alloc();
		buf = new ubyte[](1024*64);
		chunkManager = new ChunkManager();
		worldAccess = new WorldAccess(chunkManager);
		chunkObserverManager = new ChunkObserverManager();

		ubyte numLayers = 2;
		chunkManager.setup(numLayers);
		chunkManager.isChunkSavingEnabled = true;

		// Component connections
		chunkManager.startChunkSave = &chunkProvider.startChunkSave;
		chunkManager.pushLayer = &chunkProvider.pushLayer;
		chunkManager.endChunkSave = &chunkProvider.endChunkSave;
		chunkManager.loadChunkHandler = &chunkProvider.loadChunk;

		chunkProvider.onChunkLoadedHandler = &chunkManager.onSnapshotLoaded!LoadedChunkData;
		chunkProvider.onChunkSavedHandler = &chunkManager.onSnapshotSaved!SavedChunkData;

		chunkObserverManager.changeChunkNumObservers = &chunkManager.setExternalChunkObservers;
		chunkObserverManager.chunkObserverAdded = &onChunkObserverAdded;
		chunkObserverManager.loadQueueSpaceAvaliable = &chunkProvider.loadQueueSpaceAvaliable;

		activeChunks.loadChunk = &chunkObserverManager.addServerObserver;
		activeChunks.unloadChunk = &chunkObserverManager.removeServerObserver;

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

		connection = pluginman.getPlugin!NetServerPlugin;
		connection.registerPacketHandler!FillBlockVolumePacket(&handleFillBlockVolumePacket);

		chunkProvider.init(worldDb, numGenWorkersOpt.get!uint, blockPlugin.getBlocks());
		worldDb = null;
		activeChunks.loadActiveChunks();
		worldAccess.blockInfos = blockPlugin.getBlocks();
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
			foreach(saveHandler; ioManager.worldSaveHandlers) {
				saveHandler(pluginDataSaver);
			}
			chunkProvider.pushSaveHandler(&worldSaver);
		}
	}

	// executed on io thread. Stores values written into pluginDataSaver.
	private void worldSaver(WorldDb wdb)
	{
		foreach(string key, ubyte[] data; pluginDataSaver) {
			//infof("Writing %s", key);
			//printCborStream(data[]);

			wdb.putPerWorldValue(key, data);
		}
		pluginDataSaver.reset();
		atomicStore(isSaving, false);
	}

	private void loadWorld(string _worldFilename)
	{
		worldFilename = _worldFilename;
		worldDb = new WorldDb;
		worldDb.open(_worldFilename);

		worldDb.beginTxn();
		scope(exit) worldDb.abortTxn();

		auto dataLoader = PluginDataLoader(worldDb);
		foreach(loadHandler; ioManager.worldLoadHandlers) {
			loadHandler(dataLoader);
		}
	}

	private void readWorldInfo(ref PluginDataLoader loader)
	{
		import std.path : absolutePath, buildNormalizedPath;
		ubyte[] data = loader.readEntry(worldInfoKey);
		if (!data.empty) {
			worldInfo = decodeCborSingleDup!WorldInfo(data);
			infof("Loading world %s", worldFilename.absolutePath.buildNormalizedPath);
		} else {
			infof("Creating world %s", worldFilename.absolutePath.buildNormalizedPath);
		}
	}

	private void writeWorldInfo(ref PluginDataSaver saver)
	{
		size_t encodedSize = encodeCbor(saver.tempBuffer, worldInfo);
		saver.writeEntry(worldInfoKey, encodedSize);
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
		sendChanges(worldAccess.blockChanges);
		worldAccess.blockChanges = null;
	}

	private void handleStopEvent(ref GameStopEvent event)
	{
		while(atomicLoad(isSaving))
		{
			import core.thread : Thread;
			Thread.yield();
		}
		chunkProvider.stop();
		pluginDataSaver.free();
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

	private void handleFillBlockVolumePacket(ubyte[] packetData, ClientId clientId)
	{
		import voxelman.core.packets : FillBlockVolumePacket;
		if (clientDb.isSpawned(clientId))
		{
			auto packet = unpackPacketNoDup!FillBlockVolumePacket(packetData);
			worldAccess.fillVolume(packet.volume, packet.blockId);
			connection.sendToAll(packet);
		}
	}
}
