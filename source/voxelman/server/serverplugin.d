/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.server.serverplugin;

import std.experimental.logger;

import derelict.enet.enet;

import plugin;
import plugin.pluginmanager;
import netlib.connection;
import netlib.baseserver;

import voxelman.blockman;
import voxelman.config;
import voxelman.events;
import voxelman.packets;
import voxelman.plugins.eventdispatcherplugin;
import voxelman.plugins.gametimeplugin;
import voxelman.server.chunkman;
import voxelman.server.clientinfo;
import voxelman.server.events;
import voxelman.storage.chunk;
import voxelman.storage.chunkprovider;
import voxelman.storage.chunkstorage;
import voxelman.storage.coordinates;
import voxelman.storage.world;
import voxelman.utils.math;

final class ServerConnection : BaseServer!ClientInfo{}

class ServerPlugin : IPlugin
{
private:
	PluginManager pluginman = new PluginManager;
	EventDispatcherPlugin evDispatcher = new EventDispatcherPlugin;
	GameTimePlugin gameTime = new GameTimePlugin;

public:
	ServerConnection connection;

	// Game data
	BlockMan blockMan;
	ChunkMan chunkMan;
	ChunkProvider chunkProvider;
	World world;
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
		import std.random;
		randomShuffle(connection.packetArray[1..$]);
		foreach (i, packetInfo; connection.packetArray)
			packetInfo.id = i;
	}

	this()
	{
		loadEnet();

		connection = new ServerConnection;
		chunkMan = ChunkMan(connection, &world.chunkStorage);

		blockMan.loadBlockTypes();
		chunkProvider.init(WORLD_DIR, &world.chunkStorage);
		world.init(WORLD_DIR, &chunkProvider);

		chunkProvider.onChunkLoadedHandlers ~= &blockMan.onChunkLoaded;
		chunkProvider.onChunkLoadedHandlers ~= &chunkMan.onChunkLoaded;

		world.chunkStorage.onChunkAddedHandlers ~= &chunkMan.onChunkAdded;
		world.chunkStorage.onChunkAddedHandlers ~= &chunkProvider.onChunkAdded;
		world.chunkStorage.onChunkRemovedHandlers ~= &chunkMan.onChunkRemoved;
		world.chunkStorage.onChunkRemovedHandlers ~= &chunkProvider.onChunkRemoved;

		world.worldAccess.onChunkModifiedHandlers ~= &chunkMan.onChunkModified;

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
		}

		while (connection.clientStorage.length)
		{
			connection.update(0);
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
		evDispatcher.postEvent(new PreUpdateEvent(dt));

		evDispatcher.postEvent(new UpdateEvent(dt));

		connection.update(0);
		chunkProvider.update();
		world.update();
		chunkMan.sendChanges();

		evDispatcher.postEvent(new PostUpdateEvent(dt));
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

	void handleCommand(CommandEvent event)
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
	}

	void onConnect(ref ENetEvent event)
	{
		auto clientId = connection.clientStorage.addClient(event.peer);
		event.peer.data = cast(void*)clientId;
		//enet_peer_timeout(event.peer, 0, 0, 2000);
		infof("%s connected", clientId);
		evDispatcher.postEvent(new ClientConnectedEvent(clientId));

		connection.sendTo(clientId, PacketMapPacket(connection.packetNames));
	}

	void onDisconnect(ref ENetEvent event)
	{
		ClientId clientId = cast(ClientId)event.peer.data;
		infof("%s %s disconnected", clientId,
			connection.clientStorage[clientId].name);

		chunkMan.removeRegionObserver(clientId);

		evDispatcher.postEvent(new ClientDisconnectedEvent(clientId));

		// Reset client's information
		event.peer.data = null;
		connection.clientStorage.removeClient(clientId);

		connection.sendToAll(ClientLoggedOutPacket(clientId));

		infof("totalObservedChunks %s", chunkMan.totalObservedChunks);
	}

	void handleLoginPacket(ubyte[] packetData, ClientId clientId)
	{
		LoginPacket packet = unpackPacket!LoginPacket(packetData);
		ClientInfo* info = connection.clientStorage[clientId];
		info.name = packet.clientName;
		info.isLoggedIn = true;
		spawnClient(info.pos, info.heading, clientId);

		infof("%s %s logged in", clientId,
			connection.clientStorage[clientId].name);

		connection.sendTo(clientId, SessionInfoPacket(clientId, clientNames));
		connection.sendToAllExcept(clientId, ClientLoggedInPacket(clientId, packet.clientName));

		evDispatcher.postEvent(new ClientLoggedInEvent(clientId));
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
			auto commandEvent = new CommandEvent(clientId, strippedMsg);
			evDispatcher.postEvent(commandEvent);
			return;
		}

		connection.sendToAll(packet);
	}

	void handleClientPosition(ubyte[] packetData, ClientId clientId)
	{
		ClientInfo* clientInfo = connection.clientStorage[clientId];
		if (clientInfo.isLoggedIn)
		{
			auto packet = unpackPacket!ClientPositionPacket(packetData);
			//infof("Received ClientPositionPacket(%s, %s, %s)",
			//	packet.x, packet.y, packet.z);

			clientInfo.pos = packet.pos;
			clientInfo.heading = packet.heading;
			chunkMan.updateObserverPosition(clientId);
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
		chunkMan.updateObserverPosition(clientId);
	}

	void handlePlaceBlockPacket(ubyte[] packetData, ClientId clientId)
	{
		auto packet = unpackPacket!PlaceBlockPacket(packetData);
		//infof("Received PlaceBlockPacket(%s)", packet);

		world.worldAccess.setBlock(BlockWorldPos(packet.blockPos), packet.blockType);
	}
}
