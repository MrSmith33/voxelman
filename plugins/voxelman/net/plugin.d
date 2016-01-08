/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.net.plugin;

import derelict.enet.enet;

import pluginlib;
public import netlib;

import voxelman.net.events;
import voxelman.eventdispatcher.plugin;

shared static this()
{
	pluginRegistry.regClientPlugin(new NetClientPlugin);
	pluginRegistry.regServerPlugin(new NetServerPlugin);
}

mixin template NetBase()
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
	mixin NetBase;

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
	mixin NetBase;

	BaseServer connection;
	alias connection this;

	this() {
		connection = new class BaseServer{};
	}

	void onConnect(ref ENetEvent event) {
		auto clientId = clientStorage.addClient(event.peer);
		event.peer.data = cast(void*)clientId;

		evDispatcher.postEvent(ClientConnectedEvent(clientId));
	}

	void onDisconnect(ref ENetEvent event) {
		ClientId clientId = cast(ClientId)event.peer.data;
		event.peer.data = null;

		clientStorage.removeClient(clientId);

		evDispatcher.postEvent(ClientDisconnectedEvent(clientId));
	}
}
