/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.serverworld;

import std.array : empty;
import core.atomic : atomicStore, atomicLoad;

import cbor;
import netlib;
import pluginlib;

import voxelman.container.buffer;
import voxelman.log;
import voxelman.math;

import voxelman.core.config;
import voxelman.core.events;
import voxelman.net.events;
import voxelman.utils.compression;

import voxelman.input.keybindingmanager;
import voxelman.config.configmanager : ConfigOption, ConfigManager;
import voxelman.eventdispatcher.plugin : EventDispatcherPlugin;
import voxelman.net.plugin : NetServerPlugin;
import voxelman.session.server;
import voxelman.block.plugin;
import voxelman.blockentity.plugin;
import voxelman.dbg.plugin;

import voxelman.net.packets;
import voxelman.core.packets;

import voxelman.world.blockentity.blockentityaccess;
import voxelman.world.gen.generators;
import voxelman.world.storage;
import voxelman.world.storage.dimensionobservermanager;

public import voxelman.world.worlddb : WorldDb;

enum START_NEW_WORLD = false;

struct IdMapManagerServer
{
	string[][string] idMaps;
	void regIdMap(string name, string[] mapItems)
	{
		idMaps[name] = mapItems;
	}
}

struct WorldInfo
{
	string name = DEFAULT_WORLD_NAME;
	TimestampType simulationTick;
	ClientDimPos spawnPos;
	DimensionId spawnDimension;
}

//version = DBG_COMPR;
final class ServerWorld : IPlugin
{
private:
	EventDispatcherPlugin evDispatcher;
	NetServerPlugin connection;
	ClientManager clientMan;
	BlockPluginServer blockPlugin;
	BlockEntityServer blockEntityPlugin;

	Debugger dbg;

	ConfigOption numGenWorkersOpt;
	ConfigOption saveUnmodifiedChunksOpt;

	ubyte[] buf;
	auto dbKey = IoKey("voxelman.world.world_info");
	string worldFilename;

	shared bool isSaving;
	IoManager ioManager;
	WorldDb worldDb;
	PluginDataSaver pluginDataSaver;

public:
	ChunkManager chunkManager;
	ChunkProvider chunkProvider;
	ChunkObserverManager chunkObserverManager;

	DimensionManager dimMan;
	DimensionObserverManager dimObserverMan;

	ActiveChunks activeChunks;
	IdMapManagerServer idMapManager;

	WorldInfo worldInfo;
	WorldAccess worldAccess;
	BlockEntityAccess entityAccess;

	mixin IdAndSemverFrom!"voxelman.world.plugininfo";

	override void registerResourceManagers(void delegate(IResourceManager) registerHandler)
	{
		ioManager = new IoManager(&loadWorld);
		registerHandler(ioManager);
	}

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		ConfigManager config = resmanRegistry.getResourceManager!ConfigManager;
		numGenWorkersOpt = config.registerOption!int("num_workers", 4);
		saveUnmodifiedChunksOpt = config.registerOption!bool("save_unmodified_chunks", false);

		ioManager.registerWorldLoadSaveHandlers(&readWorldInfo, &writeWorldInfo);
		ioManager.registerWorldLoadSaveHandlers(&activeChunks.read, &activeChunks.write);
		ioManager.registerWorldLoadSaveHandlers(&dimMan.load, &dimMan.save);

		dimMan.generatorMan.factory.registerGenerator!GeneratorFlat;
		dimMan.generatorMan.factory.registerGenerator!Generator2d;
		dimMan.generatorMan.factory.registerGenerator!Generator2d3d;

		dbg = resmanRegistry.getResourceManager!Debugger;
	}

	override void preInit()
	{
		pluginDataSaver.stringMap = &ioManager.stringMap;
		idMapManager.regIdMap("string_map", ioManager.stringMap.strings);

		buf = new ubyte[](1024*64*4);
		chunkManager = new ChunkManager();
		worldAccess = new WorldAccess(chunkManager);
		entityAccess = new BlockEntityAccess(chunkManager);
		chunkObserverManager = new ChunkObserverManager();

		chunkManager.setup(NUM_CHUNK_LAYERS);
		chunkManager.setLayerInfo(ChunkLayerInfo(BLOCK_METADATA_UNIFORM_FILL_BITS), METADATA_LAYER);
		chunkManager.isChunkSavingEnabled = true;

		// Component connections
		chunkManager.startChunkSave = &chunkProvider.startChunkSave;
		chunkManager.pushLayer = &chunkProvider.pushLayer;
		chunkManager.endChunkSave = &chunkProvider.endChunkSave;
		chunkManager.loadChunkHandler = &chunkProvider.loadChunk;
		chunkManager.cancelLoadChunkHandler = &chunkProvider.cancelLoad;

		chunkProvider.onChunkLoadedHandler = &chunkManager.onSnapshotLoaded;
		chunkProvider.onChunkSavedHandler = &chunkManager.onSnapshotSaved;
		chunkProvider.generatorGetter = &dimMan.generatorMan.opIndex;

		chunkObserverManager.changeChunkNumObservers = &chunkManager.setExternalChunkObservers;
		chunkObserverManager.chunkObserverAdded = &onChunkObserverAdded;
		chunkObserverManager.loadQueueSpaceAvaliable = &chunkProvider.loadQueueSpaceAvaliable;

		dimObserverMan.dimensionObserverAdded = &onDimensionObserverAdded;

		activeChunks.loadChunk = &chunkObserverManager.addServerObserver;
		activeChunks.unloadChunk = &chunkObserverManager.removeServerObserver;

		chunkManager.onChunkLoadedHandler = &onChunkLoaded;
	}

	override void init(IPluginManager pluginman)
	{
		blockPlugin = pluginman.getPlugin!BlockPluginServer;
		clientMan = pluginman.getPlugin!ClientManager;

		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&handlePreUpdateEvent);
		evDispatcher.subscribeToEvent(&handlePostUpdateEvent);
		evDispatcher.subscribeToEvent(&handleStopEvent);
		evDispatcher.subscribeToEvent(&handleClientDisconnected);
		evDispatcher.subscribeToEvent(&handleSaveEvent);
		evDispatcher.subscribeToEvent(&handleClientConnectedEvent);

		blockEntityPlugin = pluginman.getPlugin!BlockEntityServer;

		connection = pluginman.getPlugin!NetServerPlugin;
		connection.registerPacketHandler!FillBlockBoxPacket(&handleFillBlockBoxPacket);
		connection.registerPacketHandler!PlaceBlockEntityPacket(&handlePlaceBlockEntityPacket);
		connection.registerPacketHandler!RemoveBlockEntityPacket(&handleRemoveBlockEntityPacket);

		chunkProvider.init(worldDb, numGenWorkersOpt.get!uint,
			blockPlugin.getBlocks(), saveUnmodifiedChunksOpt.get!bool);
		worldDb = null;
		activeChunks.loadActiveChunks();
		worldAccess.blockInfos = blockPlugin.getBlocks();
	}

	TimestampType currentTimestamp() @property
	{
		return worldInfo.simulationTick;
	}

	void setDimensionBorders(DimensionId dim, Box borders)
	{
		DimensionInfo* dimInfo = dimMan.getOrCreate(dim);
		dimInfo.borders = borders;
		sendDimensionBorders(dim);
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
		foreach(ubyte[16] key, ubyte[] data; pluginDataSaver) {
			if (data.length == 0)
				wdb.del(key);
			wdb.put(key, data);
		}
		pluginDataSaver.reset();
		atomicStore(isSaving, false);
	}

	private void loadWorld(string _worldFilename)
	{
		worldFilename = _worldFilename;
		worldDb = new WorldDb;
		static if (START_NEW_WORLD)
		{
			static import std.file;
			if (std.file.exists(_worldFilename))
			{
				std.file.remove(_worldFilename);
			}
		}
		worldDb.open(_worldFilename);

		worldDb.beginTxn();
		scope(exit) worldDb.abortTxn();

		auto dataLoader = PluginDataLoader(&ioManager.stringMap, worldDb);
		foreach(loadHandler; ioManager.worldLoadHandlers) {
			loadHandler(dataLoader);
		}
	}

	private void readWorldInfo(ref PluginDataLoader loader)
	{
		import std.path : absolutePath, buildNormalizedPath;
		ubyte[] data = loader.readEntryRaw(dbKey);
		if (!data.empty) {
			worldInfo = decodeCborSingleDup!WorldInfo(data);
			infof("Loading world %s", worldFilename.absolutePath.buildNormalizedPath);
		} else {
			infof("Creating world %s", worldFilename.absolutePath.buildNormalizedPath);
			createWorld();
		}
	}

	void createWorld()
	{
		dimMan.generatorMan[0] = new GeneratorFlat;
		dimMan.generatorMan[1] = new Generator2d;
		dimMan.generatorMan[2] = new Generator2d3d;
	}

	private void writeWorldInfo(ref PluginDataSaver saver)
	{
		saver.writeEntryEncoded(dbKey, worldInfo);
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

		import voxelman.world.gen.generators;
		import core.atomic;
		dbg.setVar("gen cache hits", atomicLoad(cache_hits));
		dbg.setVar("gen cache misses", atomicLoad(cache_misses));
		dbg.setVar("total loads", chunkProvider.totalReceived);
		dbg.setVar("canceled loads", chunkProvider.numSuccessfulCancelations);
		dbg.setVar("wasted loads", chunkProvider.numWastedLoads);
	}

	private void handleStopEvent(ref GameStopEvent event)
	{
		while(atomicLoad(isSaving))
		{
			import core.thread : Thread;
			Thread.yield();
		}
		chunkProvider.stop();
	}

	private void onDimensionObserverAdded(DimensionId dimensionId, SessionId sessionId)
	{
		sendDimensionBorders(sessionId, dimensionId);
	}

	private void onChunkObserverAdded(ChunkWorldPos cwp, SessionId sessionId)
	{
		sendChunk(sessionId, cwp);
	}

	private void handleClientConnectedEvent(ref ClientConnectedEvent event)
	{
		foreach(key, idmap; idMapManager.idMaps)
		{
			connection.sendTo(event.sessionId, IdMapPacket(key, idmap));
		}
	}

	private void handleClientDisconnected(ref ClientDisconnectedEvent event)
	{
		chunkObserverManager.removeObserver(event.sessionId);
		dimObserverMan.removeObserver(event.sessionId);
	}

	private void onChunkLoaded(ChunkWorldPos cwp)
	{
		sendChunk(chunkObserverManager.getChunkObservers(cwp), cwp);
	}

	private void sendDimensionBorders(SessionId sessionId, DimensionId dim)
	{
		if (auto dimInfo = dimMan[dim])
			connection.sendTo(sessionId, DimensionInfoPacket(dim, dimInfo.borders));
	}

	private void sendDimensionBorders(DimensionId dim)
	{
		static Buffer!SessionId sessionBuffer;
		if (auto dimInfo = dimMan[dim])
		{
			foreach(sessionId; dimObserverMan.getDimensionObservers(dim))
				sessionBuffer.put(sessionId);

			connection.sendTo(sessionBuffer.data, DimensionInfoPacket(dim, dimInfo.borders));
			sessionBuffer.clear();
		}
	}

	private void sendChunk(S)(S sessions, ChunkWorldPos cwp)
	{
		import voxelman.core.packets : ChunkDataPacket;

		if (!chunkManager.isChunkLoaded(cwp)) return;
		ChunkLayerData[NUM_CHUNK_LAYERS] layerBuf;
		size_t compressedSize;

		ubyte numChunkLayers;
		foreach(ubyte layerId; 0..chunkManager.numLayers)
		{
			if (!chunkManager.hasSnapshot(cwp, layerId)) continue;

			auto layer = chunkManager.getChunkSnapshot(cwp, layerId);
			assert(!layer.isNull);

			version(DBG_COMPR)if (layer.type != StorageType.uniform)
			{
				ubyte[] compactBlocks = layer.getArray!ubyte;
				infof("Send %s %s %s\n(%(%02x%))", cwp, compactBlocks.ptr, compactBlocks.length, cast(ubyte[])compactBlocks);
			}

			ChunkLayerData bd = toBlockData(layer, layerId);
			if (layer.type == StorageType.fullArray)
			{
				ubyte[] compactBlocks = compressLayerData(layer.getArray!ubyte, buf[compressedSize..$]);
				compressedSize += compactBlocks.length;
				bd.blocks = compactBlocks;
			}
			layerBuf[numChunkLayers] = bd;

			++numChunkLayers;
		}

		connection.sendTo(sessions, ChunkDataPacket(cwp.ivector, layerBuf[0..numChunkLayers]));
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

	private void handleFillBlockBoxPacket(ubyte[] packetData, SessionId sessionId)
	{
		import voxelman.core.packets : FillBlockBoxPacket;
		if (clientMan.isSpawned(sessionId))
		{
			auto packet = unpackPacketNoDup!FillBlockBoxPacket(packetData);
			// TODO send to observers only.
			worldAccess.fillBox(packet.box, packet.blockId, packet.blockMeta);
			connection.sendToAll(packet);
		}
	}

	private void handlePlaceBlockEntityPacket(ubyte[] packetData, SessionId sessionId)
	{
		auto packet = unpackPacket!PlaceBlockEntityPacket(packetData);
		placeEntity(
			packet.box, packet.data,
			worldAccess, entityAccess);

		// TODO send to observers only.
		connection.sendToAll(packet);
	}

	private void handleRemoveBlockEntityPacket(ubyte[] packetData, SessionId peer)
	{
		auto packet = unpackPacket!RemoveBlockEntityPacket(packetData);
		WorldBox vol = removeEntity(BlockWorldPos(packet.blockPos),
			blockEntityPlugin.blockEntityInfos, worldAccess, entityAccess, /*AIR*/1);
		//infof("Remove entity at %s", vol);

		connection.sendToAll(packet);
	}
}
