/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.session.client;

import std.string : format;

import datadriven : EntityId;
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
import voxelman.entity.plugin : EntityComponentRegistry;
import voxelman.eventdispatcher.plugin;
import voxelman.world.clientworld;
import voxelman.net.plugin;
import voxelman.graphics.plugin;

import voxelman.session.components;

struct ThisClientLoggedInEvent {
	EntityId thisClientId;
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
	EntityId thisSessionId;
	EntityId thisEntityId;
	string[EntityId] clientNames;
	bool isSpawned = false;

	// IPlugin stuff
	mixin IdAndSemverFrom!"voxelman.session.plugininfo";

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		ConfigManager config = resmanRegistry.getResourceManager!ConfigManager;
		nicknameOpt = config.registerOption!string("name", "Player");
		auto components = resmanRegistry.getResourceManager!EntityComponentRegistry;
		registerSessionComponents(components.eman);
	}

	override void init(IPluginManager pluginman)
	{
		graphics = pluginman.getPlugin!GraphicsPlugin;

		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&handleThisClientDisconnected);

		clientWorld = pluginman.getPlugin!ClientWorld;

		connection = pluginman.getPlugin!NetClientPlugin;
		connection.registerPacketHandler!SessionInfoPacket(&handleSessionInfoPacket);
		connection.registerPacketHandler!ClientLoggedInPacket(&handleUserLoggedInPacket);
		connection.registerPacketHandler!ClientLoggedOutPacket(&handleUserLoggedOutPacket);
		connection.registerPacketHandler!DimensionInfoPacket(&handleDimensionInfoPacket);
		connection.registerPacketHandler!ClientPositionPacket(&handleClientPositionPacket);
		connection.registerPacketHandler!SpawnPacket(&handleSpawnPacket);
		connection.registerPacketHandler!GameStartPacket(&handleGameStartPacket);
	}

	void handleThisClientDisconnected(ref ThisClientDisconnectedEvent event)
	{
		isSpawned = false;
	}

	void handleGameStartPacket(ubyte[] packetData)
	{
		connection.send(LoginPacket(nicknameOpt.get!string));
		evDispatcher.postEvent(ThisClientConnectedEvent());
		evDispatcher.postEvent(SendClientSettingsEvent());
		connection.send(GameStartPacket());
	}

	void handleUserLoggedInPacket(ubyte[] packetData)
	{
		auto newUser = unpackPacket!ClientLoggedInPacket(packetData);
		clientNames[newUser.clientId] = newUser.clientName;
		infof("%s has connected", newUser.clientName);
		evDispatcher.postEvent(ClientLoggedInEvent(newUser.clientId));
	}

	void handleUserLoggedOutPacket(ubyte[] packetData)
	{
		auto packet = unpackPacket!ClientLoggedOutPacket(packetData);
		infof("%s has disconnected", clientName(packet.clientId));
		evDispatcher.postEvent(ClientLoggedOutEvent(packet.clientId));
		clientNames.remove(packet.clientId);
	}

	void handleSessionInfoPacket(ubyte[] packetData)
	{
		auto loginInfo = unpackPacket!SessionInfoPacket(packetData);

		clientNames = loginInfo.clientNames;
		thisSessionId = loginInfo.yourId;
		thisEntityId = loginInfo.yourId;
		evDispatcher.postEvent(ThisClientLoggedInEvent(thisSessionId));
	}

	// borders have changed, affects loaded/added chunks
	void handleDimensionInfoPacket(ubyte[] packetData)
	{
		auto packet = unpackPacket!DimensionInfoPacket(packetData);
		infof("borders %s %s", packet.dimension, packet.borders);
		clientWorld.setDimensionBorders(packet.dimension, packet.borders);
	}

	// position has changed, affects loaded/added chunks
	void handleClientPositionPacket(ubyte[] packetData)
	{
		auto packet = unpackPacket!ClientPositionPacket(packetData);
		//tracef("Received ClientPositionPacket(%s, %s, %s, %s)",
		//	packet.pos, packet.heading, packet.dimension, packet.positionKey);

		nansToZero(packet.dimPos.pos);
		graphics.camera.position = vec3(packet.dimPos.pos);

		nansToZero(packet.dimPos.heading);
		graphics.camera.setHeading(vec2(packet.dimPos.heading));

		clientWorld.setCurrentDimension(packet.dimension, packet.positionKey);
	}

	void handleSpawnPacket(ubyte[] packetData)
	{
		auto packet = unpackPacket!SpawnPacket(packetData);
		isSpawned = true;
		clientWorld.updateObserverPosition();
	}

	string clientName(EntityId clientId)
	{
		return clientId in clientNames ? clientNames[clientId] : format("? %s", clientId);
	}
}
