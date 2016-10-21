/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.session.server;

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

import voxelman.command.plugin;
import voxelman.eventdispatcher.plugin;
import voxelman.net.plugin;
import voxelman.world.serverworld;

import voxelman.session.clientinfo;
import voxelman.session.clientstorage;

shared static this()
{
	pluginRegistry.regServerPlugin(new ClientManager);
}

final class ClientManager : IPlugin
{
private:
	EventDispatcherPlugin evDispatcher;
	NetServerPlugin connection;
	ServerWorld serverWorld;

public:
	ClientStorage clients;

	// IPlugin stuff
	mixin IdAndSemverFrom!(voxelman.session.plugininfo);

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
		commandPlugin.registerCommand("spawn", &onSpawnCommand);
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

	void onSpawnCommand(CommandParams params)
	{
		ClientInfo* info = clients[params.source];
		if(info is null) return;

		if (params.args.length > 1 && params.args[1] == "set")
		{
			setSpawn(info.dimension, info);
			return;
		}

		spawnClient(info, info.dimension);
		updateObserverBox(info);
	}

	void setSpawn(DimensionId dimension, ClientInfo* info)
	{
		auto dimInfo = serverWorld.dimMan.getOrCreate(dimension);
		dimInfo.spawnPos = info.pos;
		dimInfo.spawnRotation = info.heading;
		connection.sendTo(info.id, MessagePacket(0,
			format(`spawn of %s dimension is now %s`, dimension, info.pos)));
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
		connection.sendTo(info.id, ClientPositionPacket(info.pos,
			info.heading, info.dimension, info.positionKey));
		updateObserverBox(info);
	}

	void tpToPlayer(ClientInfo* info, ClientInfo* destination) {
		connection.sendTo(info.id, MessagePacket(0,
			format("Teleporting to %s", destination.name)));

		info.pos = destination.pos;
		++info.positionKey;
		connection.sendTo(info.id, ClientPositionPacket(info.pos,
			info.heading, info.dimension, info.positionKey));
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

	void spawnClient(ClientInfo* info, ushort dimension)
	{
		auto dimInfo = serverWorld.dimMan.getOrCreate(dimension);

		info.pos = dimInfo.spawnPos;
		info.heading = dimInfo.spawnRotation;
		info.dimension = dimension;
		++info.positionKey;

		connection.sendTo(info.id, ClientPositionPacket(info.pos,
			info.heading, info.dimension, info.positionKey));
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

				connection.sendTo(params.source, ClientPositionPacket(info.pos,
					info.heading, info.dimension, info.positionKey));
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
			spawnClient(info, SPAWN_DIMENSION);
			connection.sendTo(clientId, SpawnPacket());
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
