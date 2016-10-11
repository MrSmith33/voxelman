/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.session.client;

import std.string : format;

import netlib;
import pluginlib;
import voxelman.log;
import voxelman.math;

import voxelman.core.config;
import voxelman.core.events;
import voxelman.net.events;
import voxelman.core.packets;
import voxelman.net.packets;

import voxelman.config.configmanager : ConfigManager, ConfigOption;
import voxelman.eventdispatcher.plugin;
import voxelman.world.clientworld;
import voxelman.net.plugin;
import voxelman.graphics.plugin;

shared static this()
{
	pluginRegistry.regClientPlugin(new ClientSession);
}

struct ThisClientLoggedInEvent {
	ClientId thisClientId;
}

final class ClientSession : IPlugin
{
private:
	EventDispatcherPlugin evDispatcher;
	GraphicsPlugin graphics;
	NetClientPlugin connection;
	ClientWorld clientWorld;

	ConfigOption nicknameOpt;

public:
	ClientId thisClientId;
	string[ClientId] clientNames;
	bool isSpawned = false;

	// IPlugin stuff
	mixin IdAndSemverFrom!(voxelman.session.plugininfo);

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		ConfigManager config = resmanRegistry.getResourceManager!ConfigManager;
		nicknameOpt = config.registerOption!string("name", "Player");
	}

	override void init(IPluginManager pluginman)
	{
		graphics = pluginman.getPlugin!GraphicsPlugin;

		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onSendClientSettingsEvent);
		evDispatcher.subscribeToEvent(&handleThisClientDisconnected);

		clientWorld = pluginman.getPlugin!ClientWorld;

		connection = pluginman.getPlugin!NetClientPlugin;
		connection.registerPacketHandler!SessionInfoPacket(&handleSessionInfoPacket);
		connection.registerPacketHandler!ClientLoggedInPacket(&handleUserLoggedInPacket);
		connection.registerPacketHandler!ClientLoggedOutPacket(&handleUserLoggedOutPacket);
		connection.registerPacketHandler!ClientPositionPacket(&handleClientPositionPacket);
		connection.registerPacketHandler!SpawnPacket(&handleSpawnPacket);
		connection.registerPacketHandler!GameStartPacket(&handleGameStartPacket);
	}

	void onSendClientSettingsEvent(ref SendClientSettingsEvent event)
	{
		connection.send(LoginPacket(nicknameOpt.get!string));
	}

	void handleThisClientDisconnected(ref ThisClientDisconnectedEvent event)
	{
		isSpawned = false;
	}

	void handleGameStartPacket(ubyte[] packetData, ClientId clientId)
	{
		evDispatcher.postEvent(ThisClientConnectedEvent());
		evDispatcher.postEvent(SendClientSettingsEvent());
		connection.send(GameStartPacket());
	}

	void handleUserLoggedInPacket(ubyte[] packetData, ClientId clientId)
	{
		auto newUser = unpackPacket!ClientLoggedInPacket(packetData);
		clientNames[newUser.clientId] = newUser.clientName;
		infof("%s has connected", newUser.clientName);
		evDispatcher.postEvent(ClientLoggedInEvent(clientId));
	}

	void handleUserLoggedOutPacket(ubyte[] packetData, ClientId clientId)
	{
		auto packet = unpackPacket!ClientLoggedOutPacket(packetData);
		infof("%s has disconnected", clientName(packet.clientId));
		evDispatcher.postEvent(ClientLoggedOutEvent(clientId));
		clientNames.remove(packet.clientId);
	}

	void handleSessionInfoPacket(ubyte[] packetData, ClientId clientId)
	{
		auto loginInfo = unpackPacket!SessionInfoPacket(packetData);

		clientNames = loginInfo.clientNames;
		thisClientId = loginInfo.yourId;
		evDispatcher.postEvent(ThisClientLoggedInEvent(thisClientId));
	}

	void handleClientPositionPacket(ubyte[] packetData, ClientId peer)
	{
		auto packet = unpackPacket!ClientPositionPacket(packetData);
		//tracef("Received ClientPositionPacket(%s, %s, %s, %s)",
		//	packet.pos, packet.heading, packet.dimension, packet.positionKey);

		nansToZero(packet.pos);
		graphics.camera.position = vec3(packet.pos);

		nansToZero(packet.heading);
		graphics.camera.setHeading(vec2(packet.heading));

		clientWorld.setCurrentDimension(packet.dimension, packet.positionKey);
	}

	void handleSpawnPacket(ubyte[] packetData, ClientId peer)
	{
		auto packet = unpackPacket!SpawnPacket(packetData);
		isSpawned = true;
		clientWorld.updateObserverPosition();
	}

	string clientName(ClientId clientId)
	{
		return clientId in clientNames ? clientNames[clientId] : format("? %s", clientId);
	}
}
