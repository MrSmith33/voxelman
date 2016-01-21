/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.net.plugin;

import std.experimental.logger;
import derelict.enet.enet;
import std.datetime : MonoTime, Duration, usecs, dur;

import pluginlib;
public import netlib;
import derelict.enet.enet;

import voxelman.core.config;
import voxelman.net.events;
import voxelman.core.events;
import voxelman.core.packets;
import voxelman.net.packets;

import voxelman.eventdispatcher.plugin;
import voxelman.command.plugin;
import voxelman.dbg.plugin;
import voxelman.config.configmanager;

shared static this()
{
	pluginRegistry.regClientPlugin(new NetClientPlugin);
	pluginRegistry.regServerPlugin(new NetServerPlugin);
}

mixin template NetCommon()
{
	mixin IdAndSemverFrom!(voxelman.net.plugininfo);
	private EventDispatcherPlugin evDispatcher;

	override void preInit() {
		import voxelman.utils.libloader;
		loadEnet([getLibName(BUILD_TO_ROOT_PATH, "enet")]);

		connection.connectHandler = &onConnect;
		connection.disconnectHandler = &onDisconnect;
		voxelman.net.packets.registerPackets(connection);
		voxelman.core.packets.registerPackets(connection);
	}

	override void init(IPluginManager pluginman) {
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
	}
}

final class NetClientPlugin : IPlugin
{
	CommandPluginClient commandPlugin;
	Debugger dbg;

	ConfigOption serverIpOpt;
	ConfigOption serverPortOpt;
	bool isDisconnecting = false;
	void delegate(string[])[string] onMapReceivedHandlers;

	mixin NetCommon;

	BaseClient connection;
	alias connection this;

	this() {
		connection = new class BaseClient{};
	}

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		ConfigManager config = resmanRegistry.getResourceManager!ConfigManager;
		dbg = resmanRegistry.getResourceManager!Debugger;

		serverIpOpt = config.registerOption!string("ip", "127.0.0.1");
		serverPortOpt = config.registerOption!ushort("port", 1234);
	}

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&handleGameStartEvent);
		evDispatcher.subscribeToEvent(&onPreUpdateEvent);
		evDispatcher.subscribeToEvent(&onPostUpdateEvent);
		evDispatcher.subscribeToEvent(&onGameStopEvent);
		evDispatcher.subscribeToEvent(&handleThisClientConnected);
		evDispatcher.subscribeToEvent(&handleThisClientDisconnected);

		commandPlugin = pluginman.getPlugin!CommandPluginClient;
		commandPlugin.registerCommand("connect", &connectCommand);

		connection.registerPacketHandler!PacketMapPacket(&handlePacketMapPacket);
		connection.registerPacketHandler!IdMapPacket(&handleIdMapPacket);
	}

	override void postInit()
	{
	}

	void regIdMapHandler(string mapName, void delegate(string[]) onMapReceived)
	{
		onMapReceivedHandlers[mapName] = onMapReceived;
	}

	void handleGameStartEvent(ref GameStartEvent event)
	{
		ConnectionSettings settings = {null, 1, 2, 0, 0};

		connection.start(settings);
		static if (ENABLE_RLE_PACKET_COMPRESSION)
			enet_host_compress_with_range_coder(connection.host);
		connect(serverIpOpt.get!string, serverPortOpt.get!ushort);
	}

	void connect(string ip, ushort port)
	{
		infof("Connecting to %s:%s", ip, port);
		if (connection.isConnecting)
			connection.disconnect();
		connection.connect(ip, port);
	}

	void connectCommand(CommandParams params)
	{
		short port = serverPortOpt.get!ushort;
		string serverIp = serverIpOpt.get!string;
		getopt(params.args,
			"ip", &serverIp,
			"port", &port);
		connect(serverIp, port);
	}

	void onPreUpdateEvent(ref PreUpdateEvent event)
	{
		connection.update();
	}

	void onPostUpdateEvent(ref PostUpdateEvent event)
	{
		connection.flush();

		if (event.frame % 30 == 0) {
			enum maxLen = 120;
			with (connection.host) {
				dbg.logVar("Recv (B)", cast(float)totalReceivedData, maxLen);
				dbg.logVar("Send (B)", cast(float)totalSentData, maxLen);
			}
			connection.host.totalReceivedData = 0;
			connection.host.totalSentData = 0;
		}
	}

	void onConnect(ref ENetEvent event) {
	}

	void onDisconnect(ref ENetEvent event) {
		event.peer.data = null;
		evDispatcher.postEvent(ThisClientDisconnectedEvent(event.data));
	}

	void handleThisClientConnected(ref ThisClientConnectedEvent event)
	{
		infof("Connection to %s:%s established", serverIpOpt.get!string, serverPortOpt.get!ushort);
	}

	void handleThisClientDisconnected(ref ThisClientDisconnectedEvent event)
	{
		infof("disconnected with data %s", event.data);
		isDisconnecting = false;
	}

	void handlePacketMapPacket(ubyte[] packetData, ClientId clientId)
	{
		auto packetMap = unpackPacket!PacketMapPacket(packetData);
		connection.setPacketMap(packetMap.packetNames);
		connection.printPacketMap();
	}

	void handleIdMapPacket(ubyte[] packetData, ClientId clientId)
	{
		auto packet = unpackPacket!IdMapPacket(packetData);
		if (auto h = onMapReceivedHandlers.get(packet.mapName, null))
		{
			h(packet.names);
		}
	}

	void onGameStopEvent(ref GameStopEvent gameStopEvent)
	{
		import core.thread;

		if (!connection.isConnected) return;

		connection.disconnect();

		isDisconnecting = true;
		MonoTime start = MonoTime.currTime;

		size_t counter;
		while (connection.isConnected && counter < 100)
		{
			connection.update();
			Thread.sleep(1.msecs);
			++counter;
		}

		isDisconnecting = false;
		Duration disconTime = MonoTime.currTime - start;
		infof("disconnected in %s seconds",
			disconTime.total!"seconds" +
			0.001 * disconTime.total!"msecs" +
			0.000_001 * disconTime.total!"usecs");
	}
}

final class NetServerPlugin : IPlugin
{
private:
	ConfigOption portOpt;
	EventDispatcherPlugin evDispatcher;
	string[][string] idMaps;

public:
	mixin NetCommon;

	BaseServer connection;
	alias connection this;

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		ConfigManager config = resmanRegistry.getResourceManager!ConfigManager;
		portOpt = config.registerOption!ushort("port", 1234);
	}

	this()
	{
		connection = new class BaseServer{};
	}

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&handleGameStartEvent);
		evDispatcher.subscribeToEvent(&onPreUpdateEvent);
		evDispatcher.subscribeToEvent(&onPostUpdateEvent);
		evDispatcher.subscribeToEvent(&handleGameStopEvent);
	}

	override void postInit()
	{
		//connection.shufflePackets();
		connection.printPacketMap();
	}

	void regIdMap(string name, string[] mapItems)
	{
		idMaps[name] = mapItems;
	}

	void handleGameStartEvent(ref GameStartEvent event)
	{
		ConnectionSettings settings = {null, 32, 2, 0, 0};
		connection.start(settings, ENET_HOST_ANY, portOpt.get!ushort);
		static if (ENABLE_RLE_PACKET_COMPRESSION)
			enet_host_compress_with_range_coder(connection.host);
	}

	void onConnect(ref ENetEvent event) {
		auto clientId = connection.clientStorage.addClient(event.peer);
		event.peer.data = cast(void*)clientId;

		evDispatcher.postEvent(ClientConnectedEvent(clientId));
		connection.sendTo(clientId, PacketMapPacket(connection.packetNames));
		foreach(key, idmap; idMaps)
		{
			connection.sendTo(clientId, IdMapPacket(key, idmap));
		}
		connection.sendTo(clientId, GameStartPacket());
	}

	void onDisconnect(ref ENetEvent event) {
		ClientId clientId = cast(ClientId)event.peer.data;
		event.peer.data = null;
		connection.clientStorage.removeClient(clientId);
		evDispatcher.postEvent(ClientDisconnectedEvent(clientId));
	}

	void onPreUpdateEvent(ref PreUpdateEvent event)
	{
		connection.update();
	}

	void onPostUpdateEvent(ref PostUpdateEvent event)
	{
		connection.flush();
	}

	void handleGameStopEvent(ref GameStopEvent event)
	{
		connection.sendToAll(MessagePacket(0, "Stopping server"));
		connection.disconnectAll();
		while (connection.clientStorage.length)
		{
			connection.update();
		}
		connection.stop();
	}
}
