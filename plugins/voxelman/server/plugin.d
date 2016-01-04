/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.server.plugin;

import std.experimental.logger;

import derelict.enet.enet;
import tharsis.prof : Profiler, DespikerSender, Zone;

import netlib;
import pluginlib;
import pluginlib.pluginmanager;

import voxelman.utils.math;

import voxelman.core.blockman;
import voxelman.core.config;
import voxelman.core.events;

import voxelman.eventdispatcher.plugin;
import voxelman.command.plugin;
import voxelman.net.plugin;
import voxelman.config.configmanager;

import voxelman.net.events;
import voxelman.core.packets;
import voxelman.net.packets;

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

version = profiling;

shared static this()
{
	auto s = new ServerPlugin;
	pluginRegistry.regServerPlugin(s);
	pluginRegistry.regServerMain(&s.run);
}


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
			return snap.blockData.getBlockType(blockIndex);
		}
		return 0;
	}
}


class ServerPlugin : IPlugin
{
private:
	PluginManager pluginman;
	// Plugins
	EventDispatcherPlugin evDispatcher;
	CommandPlugin commandPlugin;
	NetServerPlugin connection;
	// Resource managers
	ConfigManager config;

	// Config
	ConfigOption saveDirOpt;
	ConfigOption worldNameOpt;
	ConfigOption numWorkersOpt;
	ConfigOption portOpt;

	// Profiling
	Profiler profiler;
	DespikerSender profilerSender;

public:
	ClientInfo*[ClientId] clients;

	// Game data
	BlockMan blockMan;
	ChunkProvider chunkProvider;
	ChunkManager chunkManager;
	ChunkObserverManager chunkObserverManager;
	World world;
	WorldAccess worldAccess;

	bool isRunning = false;

	mixin IdAndSemverFrom!(voxelman.server.plugininfo);

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		config = resmanRegistry.getResourceManager!ConfigManager;
		saveDirOpt = config.registerOption!string("save_dir", "../../saves");
		worldNameOpt = config.registerOption!string("world_name", "world");
		numWorkersOpt = config.registerOption!uint("num_workers", 4);
		portOpt = config.registerOption!ushort("port", 1234);
	}

	this()
	{
		version(profiling)
		{
			ubyte[] storage  = new ubyte[Profiler.maxEventBytes + 20 * 1024 * 1024];
			profiler = new Profiler(storage);
		}
		profilerSender = new DespikerSender([profiler]);

		chunkManager = new ChunkManager();
		worldAccess = new WorldAccess(&chunkManager);
		chunkObserverManager = new ChunkObserverManager();

		pluginman = new PluginManager;

		// Connections
		chunkManager.loadChunkHandler = &chunkProvider.loadChunk;
		chunkManager.saveChunkHandler = &chunkProvider.saveChunk;
		chunkProvider.onChunkLoadedHandlers ~= &chunkManager.onSnapshotLoaded;
		chunkProvider.onChunkSavedHandlers ~= &chunkManager.onSnapshotSaved;
		chunkObserverManager.changeChunkNumObservers = &chunkManager.setExternalChunkUsers;
		chunkObserverManager.chunkObserverAdded = &onChunkObserverAdded;
		chunkObserverManager.loadQueueSpaceAvaliable = &chunkProvider.loadQueueSpaceAvaliable;
		chunkManager.onChunkLoadedHandlers ~= &onChunkLoaded;
		chunkManager.chunkChangesHandlers ~= &sendChanges;
	}

	override void preInit()
	{
		auto worldDir = saveDirOpt.get!string ~ "/" ~ worldNameOpt.get!string;
		chunkProvider.init(worldDir, numWorkersOpt.get!uint);
		world.init(worldDir);
		blockMan.loadBlockTypes();

		world.load();
	}

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.profiler = profiler;

		evDispatcher.subscribeToEvent(&handleClientConnected);
		evDispatcher.subscribeToEvent(&handleClientDisconnected);

		commandPlugin = pluginman.getPlugin!CommandPlugin;
		commandPlugin.registerCommand("stop", &stopCommand);

		connection = pluginman.getPlugin!NetServerPlugin;

		static import voxelman.core.packets;
		static import voxelman.net.packets;
		connection.printPacketMap();

		connection.registerPacketHandler!LoginPacket(&handleLoginPacket);
		connection.registerPacketHandler!ClientPositionPacket(&handleClientPosition);
		connection.registerPacketHandler!PlaceBlockPacket(&handlePlaceBlockPacket);

		connection.registerPacketHandler!ViewRadiusPacket(&handleViewRadius);
		connection.registerPacketHandler!CommandPacket(&handleCommandPacket);
	}

	override void postInit()
	{
		//shufflePackets();
	}

	void load(string[] args)
	{
		// register all plugins and managers
		import voxelman.plugininforeader : filterEnabledPlugins;
		foreach(p; pluginRegistry.serverPlugins.byValue.filterEnabledPlugins(args))
		{
			pluginman.registerPlugin(p);
		}

		// Actual loading sequence
		pluginman.initPlugins();
	}

	void run(string[] args)
	{
		import std.datetime : TickDuration, Duration, Clock, usecs;
		import core.thread : Thread;
		import core.memory;

		load(args);

		ConnectionSettings settings = {null, 32, 2, 0, 0};
		connection.start(settings, ENET_HOST_ANY, portOpt.get!ushort);
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

		connection.disconnectAll();
		while (connection.clientStorage.length)
		{
			connection.update();
		}

		stop();
	}

	void update(double dt)
	{
		connection.update();
		chunkProvider.update();
		chunkObserverManager.update();
		world.update();

		evDispatcher.postEvent(PreUpdateEvent(dt));
		evDispatcher.postEvent(UpdateEvent(dt));
		evDispatcher.postEvent(PostUpdateEvent(dt));

		chunkManager.commitSnapshots(world.currentTimestamp);
		chunkManager.sendChanges();
		connection.flush();
	}

	void stop()
	{
		connection.stop();
		chunkProvider.stop();
		world.save();
	}

	void shufflePackets()
	{
		import std.random;
		randomShuffle(connection.packetArray[1..$]);
		foreach (i, packetInfo; connection.packetArray)
			packetInfo.id = i;
	}

	bool isLoggedIn(ClientId clientId)
	{
		ClientInfo* clientInfo = clients[clientId];
		return clientInfo.isLoggedIn;
	}

	string[ClientId] clientNames()
	{
		string[ClientId] names;
		foreach(id, client; clients) {
			names[id] = client.name;
		}

		return names;
	}

	auto loggerInClients()
	{
		import std.algorithm : filter, map;
		return clients.byKeyValue.filter!(a=>a.value.isLoggedIn).map!(a=>a.value.id);
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

	void onChunkObserverAdded(ChunkWorldPos cwp, ClientId clientId)
	{
		auto snap = chunkManager.getChunkSnapshot(cwp);
		if (!snap.isNull) {
			connection.sendTo(clientId,
				ChunkDataPacket(cwp.vector, snap.blockData));
		}
	}

	void stopCommand(string[] args, ClientId source)
	{
		connection.sendToAll(MessagePacket(0, "Stopping server"));
		isRunning = false;
	}

	void sendMessageTo(ClientId clientId, string message, ClientId from = 0)
	{
		connection.sendTo(clientId, MessagePacket(from, message));
	}

	void spawnClient(vec3 pos, vec2 heading, ClientId clientId)
	{
		ClientInfo* info = clients[clientId];
		info.pos = pos;
		info.heading = heading;
		connection.sendTo(clientId, ClientPositionPacket(pos, heading));
		connection.sendTo(clientId, SpawnPacket());
		updateObserverVolume(info);
	}

	void handleClientConnected(ref ClientConnectedEvent event)
	{
		clients[event.clientId] = new ClientInfo(event.clientId);
		connection.sendTo(event.clientId, PacketMapPacket(connection.packetNames));
	}

	void handleClientDisconnected(ref ClientDisconnectedEvent event)
	{
		chunkObserverManager.removeObserver(event.clientId);

		infof("%s %s disconnected", event.clientId,
			clients[event.clientId].name);

		connection.sendToAll(ClientLoggedOutPacket(event.clientId));
	}

	void handleLoginPacket(ubyte[] packetData, ClientId clientId)
	{
		LoginPacket packet = unpackPacket!LoginPacket(packetData);
		ClientInfo* info = clients[clientId];
		info.name = packet.clientName;
		info.id = clientId;
		info.isLoggedIn = true;
		spawnClient(info.pos, info.heading, clientId);

		infof("%s %s logged in", clientId, clients[clientId].name);

		connection.sendTo(clientId, SessionInfoPacket(clientId, clientNames));
		connection.sendToAllExcept(clientId, ClientLoggedInPacket(clientId, packet.clientName));

		evDispatcher.postEvent(ClientLoggedInEvent(clientId));
	}

	void handleClientPosition(ubyte[] packetData, ClientId clientId)
	{
		if (isLoggedIn(clientId))
		{
			auto packet = unpackPacket!ClientPositionPacket(packetData);
			ClientInfo* info = clients[clientId];
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
		ClientInfo* info = clients[clientId];
		info.viewRadius = clamp(packet.viewRadius,
			MIN_VIEW_RADIUS, MAX_VIEW_RADIUS);
		updateObserverVolume(info);
	}

	void handleCommandPacket(ubyte[] packetData, ClientId clientId)
	{
		auto packet = unpackPacket!CommandPacket(packetData);

		ExecResult res = commandPlugin.execute(packet.command, clientId);

		if (res.status == ExecStatus.notRegistered)
			sendMessageTo(clientId, format("Unknown command '%s'", packet.command));
		else if (res.status == ExecStatus.error)
			sendMessageTo(clientId, format("Error executing command '%s': %s", packet.command, res.error));
	}

	void updateObserverVolume(ClientInfo* info)
	{
		if (info.isLoggedIn) {
			ChunkWorldPos chunkPos = BlockWorldPos(info.pos);
			chunkObserverManager.changeObserverVolume(info.id, chunkPos, info.viewRadius);
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
