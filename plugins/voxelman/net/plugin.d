/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.net.plugin;

import derelict.enet.enet;

import pluginlib;
public import netlib;
import derelict.enet.enet;

import voxelman.core.config;
import voxelman.net.events;
import voxelman.core.events;
import voxelman.core.packets;
import voxelman.net.packets;

import voxelman.eventdispatcher.plugin;
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
	mixin NetCommon;

	BaseClient connection;
	alias connection this;

	this() {
		connection = new class BaseClient{};
	}

	void onConnect(ref ENetEvent event) {
		evDispatcher.postEvent(ThisClientConnectedEvent());
	}

	void onDisconnect(ref ENetEvent event) {
		event.peer.data = null;
		evDispatcher.postEvent(ThisClientDisconnectedEvent(event.data));
	}
}

final class NetServerPlugin : IPlugin
{
private:
	ConfigOption portOpt;
	EventDispatcherPlugin evDispatcher;

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
