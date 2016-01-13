/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.plugin;

import std.experimental.logger;
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
import voxelman.storage.world;



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

final class ClientWorld : IPlugin
{
	import voxelman.graphics.plugin;
	import voxelman.world.chunkman;
private:
	EventDispatcherPlugin evDispatcher;
	NetClientPlugin connection;
	GraphicsPlugin graphics;
	ClientDbClient clientDb;

	ConfigOption numWorkersOpt;

public:
	//ChunkManager chunkManager;
	//ChunkProvider chunkProvider;
	//ChunkObserverManager chunkObserverManager;

	//World world;
	//WorldAccess worldAccess;
	// Game stuff
	ChunkMan chunkMan;
	static import voxelman.storage.worldaccess;
	voxelman.storage.worldaccess.WorldAccess worldAccess;

	bool doUpdateObserverPosition = true;
	vec3 updatedCameraPos;

	// Send position interval
	double sendPositionTimer = 0;
	enum sendPositionInterval = 0.1;
	ChunkWorldPos prevChunkPos;

	mixin IdAndSemverFrom!(voxelman.world.plugininfo);

	override void registerResourceManagers(void delegate(IResourceManager) registerHandler) {}

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		ConfigManager config = resmanRegistry.getResourceManager!ConfigManager;
		numWorkersOpt = config.registerOption!uint("num_workers", 4);

		KeyBindingManager keyBindingMan = resmanRegistry.getResourceManager!KeyBindingManager;
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_RIGHT_BRACKET, "key.incViewRadius", null, &onIncViewRadius));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_LEFT_BRACKET, "key.decViewRadius", null, &onDecViewRadius));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_U, "key.togglePosUpdate", null, &onTogglePositionUpdate));
	}

	override void preInit()
	{
		worldAccess.init(&chunkMan.chunkStorage.getChunk, () => 0);
		worldAccess.onChunkModifiedHandlers ~= &chunkMan.onChunkChanged;

		//chunkManager = new ChunkManager();
		//worldAccess = new WorldAccess(&chunkManager);
		//chunkObserverManager = new ChunkObserverManager();
	}

	override void init(IPluginManager pluginman)
	{
		clientDb = pluginman.getPlugin!ClientDbClient;

		BlockPlugin blockPlugin = pluginman.getPlugin!BlockPlugin;
		chunkMan.init(numWorkersOpt.get!uint, blockPlugin.getBlocks());

		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onPreUpdateEvent);
		evDispatcher.subscribeToEvent(&onPostUpdateEvent);
		evDispatcher.subscribeToEvent(&onGameStopEvent);
		evDispatcher.subscribeToEvent(&onSendClientSettingsEvent);

		connection = pluginman.getPlugin!NetClientPlugin;
		connection.registerPacketHandler!ChunkDataPacket(&handleChunkDataPacket);
		connection.registerPacketHandler!MultiblockChangePacket(&handleMultiblockChangePacket);

		graphics = pluginman.getPlugin!GraphicsPlugin;
		updatedCameraPos = graphics.camera.position;
	}

	override void postInit()
	{
		chunkMan.updateObserverPosition(graphics.camera.position);
	}

	void onTogglePositionUpdate(string)
	{
		doUpdateObserverPosition = !doUpdateObserverPosition;
	}

	void onPreUpdateEvent(ref PreUpdateEvent event)
	{
		if (doUpdateObserverPosition)
		{
			updatedCameraPos = graphics.camera.position;
		}
		chunkMan.updateObserverPosition(updatedCameraPos);
		chunkMan.update();
	}

	void onPostUpdateEvent(ref PostUpdateEvent event)
	{
		if (doUpdateObserverPosition)
			sendPosition(event.deltaTime);
	}

	void onGameStopEvent(ref GameStopEvent gameStopEvent)
	{
		chunkMan.stop();
		thread_joinAll();
	}

	void onSendClientSettingsEvent(ref SendClientSettingsEvent event)
	{
		connection.send(ViewRadiusPacket(chunkMan.viewRadius));
	}

	void handleChunkDataPacket(ubyte[] packetData, ClientId peer)
	{
		import cbor;
		auto packet = decodeCborSingle!ChunkDataPacket(packetData);
		//tracef("Received %s ChunkDataPacket(%s,%s)", packetData.length,
		//	packet.chunkPos, packet.blockData.blocks.length);
		if (!packet.blockData.uniform) {
			auto blocks = uninitializedArray!(BlockId[])(CHUNK_SIZE_CUBE);
			packet.blockData.blocks = decompress(packet.blockData.blocks, blocks);
			packet.blockData.validate();
		}

		chunkMan.onChunkLoaded(ChunkWorldPos(packet.chunkPos), packet.blockData);
	}

	void handleMultiblockChangePacket(ubyte[] packetData, ClientId peer)
	{
		auto packet = unpackPacket!MultiblockChangePacket(packetData);
		Chunk* chunk = chunkMan.chunkStorage.getChunk(ChunkWorldPos(packet.chunkPos));
		// We can receive data for chunk that is already deleted.
		if (chunk is null || chunk.isMarkedForDeletion)
			return;
		chunkMan.onChunkChanged(chunk, packet.blockChanges);
	}

	void sendPosition(double dt)
	{
		ChunkWorldPos chunkPos = BlockWorldPos(graphics.camera.position);

		if (clientDb.isSpawned)
		{
			sendPositionTimer += dt;
			if (sendPositionTimer > sendPositionInterval ||
				chunkPos != prevChunkPos)
			{
				connection.send(ClientPositionPacket(
					graphics.camera.position,
					graphics.camera.heading));

				if (sendPositionTimer < sendPositionInterval)
					sendPositionTimer = 0;
				else
					sendPositionTimer -= sendPositionInterval;
			}
		}

		prevChunkPos = chunkPos;
	}

	void onIncViewRadius(string)
	{
		incViewRadius();
	}

	void onDecViewRadius(string)
	{
		decViewRadius();
	}

	void incViewRadius()
	{
		setViewRadius(getViewRadius() + 1);
	}

	void decViewRadius()
	{
		setViewRadius(getViewRadius() - 1);
	}

	int getViewRadius()
	{
		return chunkMan.viewRadius;
	}

	void setViewRadius(int newViewRadius)
	{
		import std.algorithm : clamp;
		auto oldViewRadius = chunkMan.viewRadius;
		chunkMan.viewRadius = clamp(newViewRadius,
			MIN_VIEW_RADIUS, MAX_VIEW_RADIUS);

		if (oldViewRadius != chunkMan.viewRadius)
		{
			connection.send(ViewRadiusPacket(chunkMan.viewRadius));
		}
	}
}

final class ServerWorld : IPlugin
{
private:
	EventDispatcherPlugin evDispatcher;
	NetServerPlugin connection;
	ClientDbServer clientDb;
	BlockPlugin blockPlugin;

	ConfigOption saveDirOpt;
	ConfigOption worldNameOpt;
	ConfigOption numWorkersOpt;

	ubyte[] buf;

public:
	ChunkManager chunkManager;
	ChunkProvider chunkProvider;
	ChunkObserverManager chunkObserverManager;

	World world;
	WorldAccess worldAccess;

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

		auto worldDir = saveDirOpt.get!string ~ "/" ~ worldNameOpt.get!string;
		chunkProvider.init(worldDir, numWorkersOpt.get!uint);
		world.init(worldDir);
		world.load();
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
		auto snap = chunkManager.getChunkSnapshot(cwp);
		if (!snap.isNull) {
			sendChunk(clientId, cwp, snap.blockData);
		}
	}

	void handleClientDisconnected(ref ClientDisconnectedEvent event)
	{
		chunkObserverManager.removeObserver(event.clientId);
	}

	void onChunkLoaded(ChunkWorldPos cwp, BlockDataSnapshot snap)
	{
		sendChunk(chunkObserverManager.getChunkObservers(cwp), cwp, snap.blockData);
	}

	void sendChunk(C)(C clients, ChunkWorldPos cwp, BlockData bd)
	{
		import voxelman.core.packets : ChunkDataPacket;
		import voxelman.utils.compression;
		bd.validate();
		if (!bd.uniform) bd.blocks = compress(bd.blocks, buf);
		connection.sendTo(clients, ChunkDataPacket(cwp.vector, bd));
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
		if (clientDb.isSpawned(clientId))
		{
			auto packet = unpackPacket!PlaceBlockPacket(packetData);
			worldAccess.setBlock(BlockWorldPos(packet.blockPos), packet.blockId);
		}
	}
}
