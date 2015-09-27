/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.server.serverplugin;

import std.experimental.logger;

import derelict.enet.enet;
import tharsis.prof : Profiler, DespikerSender, Zone;

import plugin;
import plugin.pluginmanager;
import resource;
import resource.resourcemanagerregistry;

import netlib.connection;
import netlib.baseserver;

import voxelman.blockman;
import voxelman.config;
import voxelman.events;
import voxelman.packets;
import voxelman.plugins.eventdispatcherplugin;
import voxelman.plugins.gametimeplugin;
import voxelman.resourcemanagers.config;
import voxelman.server.chunkman;
import voxelman.server.clientinfo;
import voxelman.server.events;
import voxelman.storage.chunk;
import voxelman.storage.chunkmanager;
import voxelman.storage.chunkobservermanager;
import voxelman.storage.chunkprovider;
import voxelman.storage.chunkstorage;
import voxelman.storage.coordinates;
import voxelman.storage.volume;
import voxelman.storage.world;
import voxelman.utils.math;

version = profiling;

final class ServerConnection : BaseServer!ClientInfo{}

final class WorldAccess {
	private ChunkManager* chunkManager;

	this(ChunkManager* chunkManager) {
		this.chunkManager = chunkManager;
	}

	bool setBlock(BlockWorldPos bwp, BlockType blockId) {
		auto blockIndex = BlockChunkIndex(bwp);
		auto chunkPos = ChunkWorldPos(bwp);
		BlockType[] blocks = chunkManager.getWriteBuffer(chunkPos);
		if (blocks is null)
			return false;
		infof("  SETB @%s", chunkPos);
		blocks[blockIndex] = blockId;

		import std.range : only;
		chunkManager.onBlockChanges(chunkPos, only(BlockChange(blockIndex.index, blockId)));
		return true;
	}

	BlockType getBlock(BlockWorldPos bwp) {
		auto blockIndex = BlockChunkIndex(bwp);
		auto chunkPos = ChunkWorldPos(bwp);
		auto snap = chunkManager.getChunkSnapshot(chunkPos);
		if (!snap.isNull) {
			return snap.blockData.blocks[blockIndex];
		}
		return 0;
	}
}

class ServerPlugin : IPlugin
{
private:
	PluginManager pluginman = new PluginManager;
	ResourceManagerRegistry resmanRegistry = new ResourceManagerRegistry;
	// Plugins
	EventDispatcherPlugin evDispatcher;
	GameTimePlugin gameTime = new GameTimePlugin;
	// Resource managers
	Config config;

	// Profiling
	Profiler profiler;
	DespikerSender profilerSender;

public:
	ServerConnection connection;

	// Game data
	BlockMan blockMan;
	ChunkProvider chunkProvider;
	ChunkManager chunkManager;
	ChunkObserverManager chunkObserverManager;
	World world;
	WorldAccess worldAccess;
	bool isRunning = false;

	// IPlugin stuff
	override string name() @property { return "ServerPlugin"; }
	override string semver() @property { return "0.4.0"; }

	override void preInit()
	{
		connection.connectHandler = &onConnect;
		connection.disconnectHandler = &onDisconnect;

		registerPackets(connection);
		//connection.printPacketMap();

		connection.registerPacketHandler!LoginPacket(&handleLoginPacket);
		connection.registerPacketHandler!MessagePacket(&handleMessagePacket);
		connection.registerPacketHandler!ClientPositionPacket(&handleClientPosition);
		connection.registerPacketHandler!PlaceBlockPacket(&handlePlaceBlockPacket);

		connection.registerPacketHandler!ViewRadiusPacket(&handleViewRadius);
	}

	override void init(IPluginManager pluginman)
	{
		evDispatcher.subscribeToEvent(&handleCommand);
	}

	override void postInit()
	{
		//shufflePackets();
	}

	void shufflePackets()
	{
		import std.random;
		randomShuffle(connection.packetArray[1..$]);
		foreach (i, packetInfo; connection.packetArray)
			packetInfo.id = i;
	}

	this()
	{
		version(profiling)
		{
			ubyte[] storage  = new ubyte[Profiler.maxEventBytes + 20 * 1024 * 1024];
			profiler = new Profiler(storage);
		}
		profilerSender = new DespikerSender([profiler]);

		loadEnet();

		evDispatcher = new EventDispatcherPlugin(profiler);
		config = new Config(SERVER_CONFIG_FILE_NAME);
		connection = new ServerConnection;

		chunkManager = new ChunkManager();

		blockMan.loadBlockTypes();
		chunkProvider.init(WORLD_DIR);
		world.init(WORLD_DIR);
		//worldAccess = WorldAccess(&chunkStorage.getChunk, &world.currentTimestamp);

		chunkManager.onChunkLoadedHandlers ~= &onChunkLoaded;
		chunkManager.chunkChangesHandlers ~= &sendChanges;
		chunkManager.loadChunkHandler = &chunkProvider.loadChunk;
		chunkManager.saveChunkHandler = &chunkProvider.saveChunk;
		chunkProvider.onChunkLoadedHandlers ~= &chunkManager.onSnapshotLoaded;
		chunkProvider.onChunkSavedHandlers ~= &chunkManager.onSnapshotSaved;
		chunkObserverManager = new ChunkObserverManager();
		chunkObserverManager.changeChunkNumObservers = &chunkManager.setExternalChunkUsers;
		worldAccess = new WorldAccess(&chunkManager);

		//chunkProvider.onChunkLoadedHandlers ~= &blockMan.onChunkLoaded;
		//chunkProvider.onChunkLoadedHandlers ~= &chunkMan.onChunkLoaded;
		//world.chunkStorage.onChunkAddedHandlers ~= &chunkMan.onChunkAdded;
		//world.chunkStorage.onChunkAddedHandlers ~= &chunkProvider.onChunkAdded;
		//world.chunkStorage.onChunkRemovedHandlers ~= &chunkMan.onChunkRemoved;
		//world.chunkStorage.onChunkRemovedHandlers ~= &chunkProvider.onChunkRemoved;
		//world.worldAccess.onChunkModifiedHandlers ~= &chunkMan.onChunkModified;

		world.load();
	}

	void run(string[] args)
	{
		import std.datetime : TickDuration, Duration, Clock, usecs;
		import core.thread : Thread;
		import core.memory;

		pluginman.registerPlugin(this);
		pluginman.registerPlugin(evDispatcher);
		pluginman.registerPlugin(gameTime);

		resmanRegistry.registerResourceManager(config);

		// Actual loading sequence
		resmanRegistry.initResourceManagers();
		pluginman.registerResources(resmanRegistry);
		resmanRegistry.loadResources();
		resmanRegistry.postInitResourceManagers();
		pluginman.initPlugins();

		ConnectionSettings settings = {null, 32, 2, 0, 0};
		connection.start(settings, ENET_HOST_ANY, SERVER_PORT);
		static if (ENABLE_RLE_PACKET_COMPRESSION)
			enet_host_compress_with_range_coder(connection.host);

		TickDuration lastTime = Clock.currAppTick;
		TickDuration newTime;
		Duration frameTime = SERVER_FRAME_TIME_USECS.usecs;

		// Main loop
		isRunning = true;
		while (isRunning)
		{
			Zone frameZone = Zone(profiler, "frame");
			newTime = Clock.currAppTick;
			double delta = (newTime - lastTime).usecs / 1_000_000.0;
			lastTime = newTime;

			update(delta);

			GC.collect();

			// update time
			auto updateTime = Clock.currAppTick - newTime;
			auto sleepTime = frameTime - updateTime;
			if (sleepTime > Duration.zero)
				Thread.sleep(sleepTime);
			version(profiling) {
				frameZone.__dtor;
				profilerSender.update();
			}
		}
		profilerSender.reset();

		while (connection.clientStorage.length)
		{
			connection.update();
		}

		stop();
	}

	void stop()
	{
		connection.stop();
		chunkProvider.stop();
		world.save();
	}

	void update(double dt)
	{
		connection.update();
		chunkProvider.update();
		world.update();

		evDispatcher.postEvent(PreUpdateEvent(dt));
		evDispatcher.postEvent(UpdateEvent(dt));
		evDispatcher.postEvent(PostUpdateEvent(dt));

		chunkManager.commitSnapshots(world.currentTimestamp);
		chunkManager.sendChanges();
		connection.flush();
	}

	bool isLoggedIn(ClientId clientId)
	{
		ClientInfo* clientInfo = connection.clientStorage[clientId];
		return clientInfo.isLoggedIn;
	}

	string[ClientId] clientNames()
	{
		string[ClientId] names;
		foreach(id, client; connection.clientStorage.clients)
		{
			names[id] = client.name;
		}

		return names;
	}

	void sendChanges(BlockChange[][ChunkWorldPos] changes)
	{
		foreach(pair; changes.byKeyValue) {
			connection.sendTo(chunkObserverManager.getChunkObservers(pair.key),
				MultiblockChangePacket(pair.key.vector, pair.value));
		}
	}

	void onChunkLoaded(ChunkWorldPos cwp, BlockDataSnapshot snap)
	{
		connection.sendTo(chunkObserverManager.getChunkObservers(cwp),
			ChunkDataPacket(cwp.vector, snap.blockData));
	}

	void handleCommand(ref CommandEvent event)
	{
		import std.algorithm : splitter;
		import std.string : format;

		if (event.command.length <= 1)
		{
			sendMessageTo(event.clientId, "Invalid command");
			return;
		}

		// Split without leading '/'
		auto splitted = event.command[1..$].splitter;
		string commName = splitted.front;
		splitted.popFront;

		if (commName == "stop")
		{
			isRunning = false;
			connection.disconnectAll();
		}
		else
			sendMessageTo(event.clientId, format("Unknown command %s", commName));
	}

	void sendMessageTo(ClientId clientId, string message, ClientId from = 0)
	{
		connection.sendTo(clientId, MessagePacket(from, message));
	}

	void spawnClient(vec3 pos, vec2 heading, ClientId clientId)
	{
		ClientInfo* info = connection.clientStorage[clientId];
		info.pos = pos;
		info.heading = heading;
		connection.sendTo(clientId, ClientPositionPacket(pos, heading));
		connection.sendTo(clientId, SpawnPacket());
		updateObserverVolume(info);
	}

	void onConnect(ref ENetEvent event)
	{
		auto clientId = connection.clientStorage.addClient(event.peer);
		event.peer.data = cast(void*)clientId;
		//enet_peer_timeout(event.peer, 0, 0, 2000);
		infof("%s connected", clientId);
		evDispatcher.postEvent(ClientConnectedEvent(clientId));

		connection.sendTo(clientId, PacketMapPacket(connection.packetNames));
	}

	void onDisconnect(ref ENetEvent event)
	{
		ClientId clientId = cast(ClientId)event.peer.data;
		infof("%s %s disconnected", clientId,
			connection.clientStorage[clientId].name);

		chunkObserverManager.removeObserver(clientId);

		evDispatcher.postEvent(ClientDisconnectedEvent(clientId));

		// Reset client's information
		event.peer.data = null;
		connection.clientStorage.removeClient(clientId);

		connection.sendToAll(ClientLoggedOutPacket(clientId));

		//infof("totalObservedChunks %s", chunkMan.totalObservedChunks);
	}

	void handleLoginPacket(ubyte[] packetData, ClientId clientId)
	{
		LoginPacket packet = unpackPacket!LoginPacket(packetData);
		ClientInfo* info = connection.clientStorage[clientId];
		info.name = packet.clientName;
		info.id = clientId;
		info.isLoggedIn = true;
		spawnClient(info.pos, info.heading, clientId);

		infof("%s %s logged in", clientId,
			connection.clientStorage[clientId].name);

		connection.sendTo(clientId, SessionInfoPacket(clientId, clientNames));
		connection.sendToAllExcept(clientId, ClientLoggedInPacket(clientId, packet.clientName));

		evDispatcher.postEvent(ClientLoggedInEvent(clientId));
	}

	void handleMessagePacket(ubyte[] packetData, ClientId clientId)
	{
		import std.algorithm : startsWith;
		import std.string : strip;

		auto packet = unpackPacket!MessagePacket(packetData);

		packet.clientId = clientId;
		string strippedMsg = packet.msg.strip;

		if (strippedMsg.startsWith("/"))
		{
			evDispatcher.postEvent(CommandEvent(clientId, strippedMsg));
			return;
		}

		connection.sendToAll(packet);
	}

	void handleClientPosition(ubyte[] packetData, ClientId clientId)
	{
		if (isLoggedIn(clientId))
		{
			auto packet = unpackPacket!ClientPositionPacket(packetData);
			ClientInfo* info = connection.clientStorage[clientId];
			info.pos = packet.pos;
			info.heading = packet.heading;
			updateObserverVolume(info);
			//infof("totalObservedChunks %s", chunkMan.totalObservedChunks);
		}
	}

	void handleViewRadius(ubyte[] packetData, ClientId clientId)
	{
		auto packet = unpackPacket!ViewRadiusPacket(packetData);
		infof("Received ViewRadiusPacket(%s)", packet.viewRadius);
		ClientInfo* info = connection.clientStorage[clientId];
		info.viewRadius = clamp(packet.viewRadius,
			MIN_VIEW_RADIUS, MAX_VIEW_RADIUS);
		updateObserverVolume(info);
	}

	void updateObserverVolume(ClientInfo* info)
	{
		if (info.isLoggedIn) {
			ChunkWorldPos chunkPos = BlockWorldPos(info.pos);
			auto volume = calcVolume(chunkPos, info.viewRadius);
			chunkObserverManager.changeObserverVolume(info.id, volume);
		}
	}

	void handlePlaceBlockPacket(ubyte[] packetData, ClientId clientId)
	{
		if (isLoggedIn(clientId))
		{
			auto packet = unpackPacket!PlaceBlockPacket(packetData);
			//infof("Received PlaceBlockPacket(%s)", packet);

			worldAccess.setBlock(BlockWorldPos(packet.blockPos), packet.blockType);
		}
	}
}
