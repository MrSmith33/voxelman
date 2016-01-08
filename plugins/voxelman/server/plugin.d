/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
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

import voxelman.core.config;
import voxelman.core.events;
import voxelman.storage.coordinates;

import voxelman.eventdispatcher.plugin : EventDispatcherPlugin;
import voxelman.command.plugin : CommandPlugin, CommandParams, ExecResult, ExecStatus;
import voxelman.net.plugin : NetServerPlugin;
import voxelman.world.plugin : ServerWorld;
import voxelman.config.configmanager : ConfigOption, ConfigManager;

import voxelman.net.events;
import voxelman.core.packets;
import voxelman.net.packets;

import voxelman.server.clientinfo;
import voxelman.server.events;

version = profiling;

shared static this()
{
	auto s = new ServerPlugin;
	pluginRegistry.regServerPlugin(s);
	pluginRegistry.regServerMain(&s.run);
}

class ServerPlugin : IPlugin
{
private:
	PluginManager pluginman;
	EventDispatcherPlugin evDispatcher;
	CommandPlugin commandPlugin;
	NetServerPlugin connection;
	ServerWorld serverWorld;

	// Config
	ConfigOption portOpt;

	// Profiling
	Profiler profiler;
	DespikerSender profilerSender;

public:
	ClientInfo*[ClientId] clients;
	bool isRunning = false;

	mixin IdAndSemverFrom!(voxelman.server.plugininfo);

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		ConfigManager config = resmanRegistry.getResourceManager!ConfigManager;
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
		pluginman = new PluginManager;
	}

	override void preInit() {}

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.profiler = profiler;

		evDispatcher.subscribeToEvent(&handleClientConnected);
		evDispatcher.subscribeToEvent(&handleClientDisconnected);

		commandPlugin = pluginman.getPlugin!CommandPlugin;
		commandPlugin.registerCommand("sv_stop|stop", &stopCommand);
		commandPlugin.registerCommand("msg", &messageCommand);

		serverWorld = pluginman.getPlugin!ServerWorld;
		connection = pluginman.getPlugin!NetServerPlugin;

		static import voxelman.core.packets;
		static import voxelman.net.packets;
		connection.printPacketMap();

		connection.registerPacketHandler!LoginPacket(&handleLoginPacket);
		connection.registerPacketHandler!ClientPositionPacket(&handleClientPosition);

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
		import voxelman.pluginlib.plugininforeader : filterEnabledPlugins;
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

		connection.stop();
		evDispatcher.postEvent(GameStopEvent());
	}

	void update(double dt)
	{
		connection.update();
		evDispatcher.postEvent(PreUpdateEvent(dt));
		evDispatcher.postEvent(UpdateEvent(dt));
		evDispatcher.postEvent(PostUpdateEvent(dt));
		connection.flush();
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

	string clientName(ClientId clientId)
	{
		auto cl = clients.get(clientId, null);
		return cl ? cl.name : format("%s", clientId);
	}

	auto loggedInClients()
	{
		import std.algorithm : filter, map;
		return clients.byKeyValue.filter!(a=>a.value.isLoggedIn).map!(a=>a.value.id);
	}

	void stopCommand(CommandParams params)
	{
		connection.sendToAll(MessagePacket(0, "Stopping server"));
		isRunning = false;
	}

	void messageCommand(CommandParams params)
	{
		import std.string : strip;
		auto stripped = params.rawArgs.strip;
		connection.sendToAll(MessagePacket(0, stripped));
		infof("> %s", stripped);
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
		serverWorld.chunkObserverManager.removeObserver(event.clientId);

		infof("%s %s disconnected", event.clientId,
			clients[event.clientId].name);

		connection.sendToAll(ClientLoggedOutPacket(event.clientId));
		clients.remove(event.clientId);
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
			serverWorld.chunkObserverManager.changeObserverVolume(info.id, chunkPos, info.viewRadius);
		}
	}
}
