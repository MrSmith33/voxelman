/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.login.plugin;

import voxelman.log;
import std.string : format;
import netlib;
import pluginlib;
import voxelman.math;

import voxelman.core.config;
import voxelman.core.events;
import voxelman.net.events;
import voxelman.core.packets;
import voxelman.net.packets;
import voxelman.world.storage.coordinates;

import voxelman.config.configmanager : ConfigManager, ConfigOption;
import voxelman.command.plugin;
import voxelman.eventdispatcher.plugin;
import voxelman.net.plugin;
import voxelman.world.serverworld;
import voxelman.world.clientworld;
import voxelman.graphics.plugin;

import voxelman.login.clientinfo;

shared static this()
{
	pluginRegistry.regClientPlugin(new ClientDbClient);
	pluginRegistry.regServerPlugin(new ClientDbServer);
}

struct ThisClientLoggedInEvent {
	ClientId thisClientId;
}

final class ClientDbClient : IPlugin
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
	mixin IdAndSemverFrom!(voxelman.login.plugininfo);

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

struct ClientStorage
{
	ClientInfo*[ClientId] clientsById;
	ClientInfo*[string] clientsByName;

	void put(ClientInfo* info) {
		assert(info);
		clientsById[info.id] = info;
	}

	size_t length() {
		return clientsById.length;
	}

	void setClientName(ClientInfo* info, string newName) {
		assert(info);
		assert(info.id in clientsById);

		if (info.name == newName) return;

		assert(info.name !in clientsByName);
		clientsByName.remove(info.name);
		if (newName) {
			clientsByName[newName] = info;
		}
		info.name = newName;
	}

	ClientInfo* opIndex(ClientId clientId) {
		return clientsById.get(clientId, null);
	}

	ClientInfo* opIndex(string name) {
		return clientsByName.get(name, null);
	}

	void remove(ClientId clientId) {
		auto info = clientsById.get(clientId, null);
		if (info) {
			clientsByName.remove(info.name);
		}
		clientsById.remove(clientId);
	}

	auto byValue() {
		return clientsById.byValue;
	}
}

final class ClientDbServer : IPlugin
{
private:
	EventDispatcherPlugin evDispatcher;
	NetServerPlugin connection;
	ServerWorld serverWorld;

public:
	ClientStorage clients;

	// IPlugin stuff
	mixin IdAndSemverFrom!(voxelman.login.plugininfo);

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		connection = pluginman.getPlugin!NetServerPlugin;
		serverWorld = pluginman.getPlugin!ServerWorld;

		evDispatcher.subscribeToEvent(&handleClientConnected);
		evDispatcher.subscribeToEvent(&handleClientDisconnected);

		connection.registerPacketHandler!LoginPacket(&handleLoginPacket);
		connection.registerPacketHandler!ViewRadiusPacket(&handleViewRadius);
		connection.registerPacketHandler!ClientPositionPacket(&handleClientPosition);
		connection.registerPacketHandler!GameStartPacket(&handleGameStartPacket);

		auto commandPlugin = pluginman.getPlugin!CommandPluginServer;
		commandPlugin.registerCommand("spawn", &onSpawn);
		commandPlugin.registerCommand("tp", &onTeleport);
		commandPlugin.registerCommand("dim", &changeDimensionCommand);
		commandPlugin.registerCommand("add_active", &onAddActive);
		commandPlugin.registerCommand("remove_active", &onRemoveActive);
	}

	void onAddActive(CommandParams params) {
		auto cwp = clients[params.source].chunk;
		serverWorld.activeChunks.add(cwp);
		infof("add active %s", cwp);
	}

	void onRemoveActive(CommandParams params) {
		auto cwp = clients[params.source].chunk;
		serverWorld.activeChunks.remove(cwp);
		infof("remove active %s", cwp);
	}

	void onSpawn(CommandParams params)
	{
		ClientInfo* info = clients[params.source];
		if(info is null) return;
		info.pos = START_POS;
		info.heading = vec2(0,0);
		info.dimension = 0;
		info.positionKey = 0;
		connection.sendTo(params.source, ClientPositionPacket(info.pos.arrayof,
			info.heading.arrayof, info.dimension, info.positionKey));
		updateObserverBox(info);
	}

	void onTeleport(CommandParams params)
	{
		import std.regex : matchFirst, regex;
		import std.conv : to;
		ClientInfo* info = clients[params.source];
		if(info is null) return;

		vec3 pos;

		auto regex3 = regex(`(-?\d+)\W+(-?\d+)\W+(-?\d+)`, "m");
		auto captures3 = matchFirst(params.rawArgs, regex3);


		if (!captures3.empty)
		{
			pos.x = to!int(captures3[1]);
			pos.y = to!int(captures3[2]);
			pos.z = to!int(captures3[3]);
			return tpToPos(info, pos);
		}

		auto regex2 = regex(`(-?\d+)\W+(-?\d+)`, "m");
		auto captures2 = matchFirst(params.rawArgs, regex2);
		if (!captures2.empty)
		{
			pos.x = to!int(captures2[1]);
			pos.y = info.pos.y;
			pos.z = to!int(captures2[2]);
			return tpToPos(info, pos);
		}

		auto regex1 = regex(`[a-Z]+[_a-Z0-9]+`);
		auto captures1 = matchFirst(params.rawArgs, regex1);
		if (!captures1.empty)
		{
			string destName = to!string(captures1[1]);
			ClientInfo* destination = clients[destName];
			if(destination is null)
			{
				connection.sendTo(params.source, MessagePacket(0,
					format(`Player "%s" is not online`, destName)));
				return;
			}
			return tpToPlayer(info, destination);
		}

		connection.sendTo(params.source, MessagePacket(0,
			`Wrong syntax: "tp <x> [<y>] <z>" | "tp <player>"`));
	}

	void tpToPos(ClientInfo* info, vec3 pos) {
		connection.sendTo(info.id, MessagePacket(0,
			format("Teleporting to %s %s %s", pos.x, pos.y, pos.z)));

		info.pos = pos;
		++info.positionKey;
		connection.sendTo(info.id, ClientPositionPacket(info.pos.arrayof,
			info.heading.arrayof, info.dimension, info.positionKey));
		updateObserverBox(info);
	}

	void tpToPlayer(ClientInfo* info, ClientInfo* destination) {
		connection.sendTo(info.id, MessagePacket(0,
			format("Teleporting to %s", destination.name)));

		info.pos = destination.pos;
		++info.positionKey;
		connection.sendTo(info.id, ClientPositionPacket(info.pos.arrayof,
			info.heading.arrayof, info.dimension, info.positionKey));
		updateObserverBox(info);
	}

	bool isLoggedIn(ClientId clientId)
	{
		ClientInfo* clientInfo = clients[clientId];
		return clientInfo.isLoggedIn;
	}

	bool isSpawned(ClientId clientId)
	{
		ClientInfo* clientInfo = clients[clientId];
		return clientInfo.isSpawned;
	}

	string[ClientId] clientNames()
	{
		string[ClientId] names;
		foreach(client; clients.byValue) {
			names[client.id] = client.name;
		}

		return names;
	}

	string clientName(ClientId clientId)
	{
		auto cl = clients[clientId];
		return cl ? cl.name : format("%s", clientId);
	}

	auto loggedInClients()
	{
		import std.algorithm : filter, map;
		return clients.byValue.filter!(a=>a.isLoggedIn).map!(a=>a.id);
	}

	void spawnClient(vec3 pos, vec2 heading, ushort dimension, ClientId clientId)
	{
		ClientInfo* info = clients[clientId];
		info.pos = pos;
		info.heading = heading;
		info.dimension = dimension;
		++info.positionKey;
		connection.sendTo(clientId, ClientPositionPacket(pos.arrayof, heading.arrayof, dimension, info.positionKey));
		connection.sendTo(clientId, SpawnPacket());
		updateObserverBox(info);
	}

	void handleClientConnected(ref ClientConnectedEvent event)
	{
		clients.put(new ClientInfo(event.clientId));
	}

	void handleClientDisconnected(ref ClientDisconnectedEvent event)
	{
		infof("%s %s disconnected", event.clientId,
			clients[event.clientId].name);

		connection.sendToAll(ClientLoggedOutPacket(event.clientId));
		clients.remove(event.clientId);
	}

	void changeDimensionCommand(CommandParams params)
	{
		import std.conv : to, ConvException;

		ClientInfo* info = clients[params.source];
		if (info.isSpawned)
		{
			if (params.args.length > 1)
			{
				auto dim = to!DimensionId(params.args[1]);
				if (dim == info.dimension)
					return;

				info.dimension = dim;
				++info.positionKey;
				updateObserverBox(info);

				connection.sendTo(params.source, ClientPositionPacket(info.pos.arrayof,
					info.heading.arrayof, info.dimension, info.positionKey));
			}
		}
	}

	void updateObserverBox(ClientInfo* info)
	{
		if (info.isSpawned) {
			serverWorld.chunkObserverManager.changeObserverBox(info.id, info.chunk, info.viewRadius);
		}
	}

	void handleLoginPacket(ubyte[] packetData, ClientId clientId)
	{
		auto packet = unpackPacket!LoginPacket(packetData);
		ClientInfo* info = clients[clientId];
		// TODO: correctly handle clients with the same name.
		clients.setClientName(info, packet.clientName);
		info.isLoggedIn = true;

		infof("%s %s logged in", clientId, clients[clientId].name);

		connection.sendTo(clientId, SessionInfoPacket(clientId, clientNames));
		connection.sendToAllExcept(clientId, ClientLoggedInPacket(clientId, packet.clientName));

		evDispatcher.postEvent(ClientLoggedInEvent(clientId));
	}

	void handleGameStartPacket(ubyte[] packetData, ClientId clientId)
	{
		if (isLoggedIn(clientId))
		{
			ClientInfo* info = clients[clientId];
			info.isSpawned = true;
			spawnClient(info.pos, info.heading, info.dimension, clientId);
		}
	}

	void handleViewRadius(ubyte[] packetData, ClientId clientId)
	{
		import std.algorithm : clamp;
		auto packet = unpackPacket!ViewRadiusPacket(packetData);
		ClientInfo* info = clients[clientId];
		info.viewRadius = clamp(packet.viewRadius,
			MIN_VIEW_RADIUS, MAX_VIEW_RADIUS);
		updateObserverBox(info);
	}

	void handleClientPosition(ubyte[] packetData, ClientId clientId)
	{
		if (isSpawned(clientId))
		{
			auto packet = unpackPacket!ClientPositionPacket(packetData);
			ClientInfo* info = clients[clientId];

			// reject stale position. Dimension already have changed.
			if (packet.positionKey != info.positionKey)
				return;

			info.pos = vec3(packet.pos);
			info.heading = vec2(packet.heading);
			updateObserverBox(info);
		}
	}
}
