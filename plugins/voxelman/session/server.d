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
import datadriven;
import voxelman.math;

import voxelman.core.config;
import voxelman.core.events;
import voxelman.net.events;
import voxelman.core.packets;
import voxelman.net.packets;
import voxelman.world.storage;

import voxelman.command.plugin;
import voxelman.eventdispatcher.plugin;
import voxelman.entity.plugin : EntityComponentRegistry;
import voxelman.net.plugin;
import voxelman.world.serverworld;

import voxelman.session.components;
import voxelman.session.clientdb;
import voxelman.session.sessionman;


final class ClientManager : IPlugin
{
private:
	EventDispatcherPlugin evDispatcher;
	NetServerPlugin connection;
	ServerWorld serverWorld;

public:
	ClientDb db;
	SessionManager sessions;

	// IPlugin stuff
	mixin IdAndSemverFrom!(voxelman.session.plugininfo);

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto ioman = resmanRegistry.getResourceManager!IoManager;
		ioman.registerWorldLoadSaveHandlers(&db.load, &db.save);
		auto components = resmanRegistry.getResourceManager!EntityComponentRegistry;
		db.eman = components.eman;
		registerSessionComponents(db.eman);
	}

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
		Session* session = sessions[params.source];
		auto position = db.get!ClientPosition(session.dbKey);
		auto cwp = position.chunk;
		serverWorld.activeChunks.add(cwp);
		infof("add active %s", cwp);
	}

	void onRemoveActive(CommandParams params) {
		Session* session = sessions[params.source];
		auto position = db.get!ClientPosition(session.dbKey);
		auto cwp = position.chunk;
		serverWorld.activeChunks.remove(cwp);
		infof("remove active %s", cwp);
	}

	void onSpawnCommand(CommandParams params)
	{
		Session* session = sessions[params.source];
		if(session is null) return;

		auto position = db.get!ClientPosition(session.dbKey);
		if (params.args.length > 1 && params.args[1] == "set")
		{
			setSpawn(position.dimension, session);
			return;
		}

		setClientDimension(session, position.dimension);
		spawnClient(session);
		updateObserverBox(session);
	}

	void setSpawn(DimensionId dimension, Session* session)
	{
		auto dimInfo = serverWorld.dimMan.getOrCreate(dimension);
		auto position = db.get!ClientPosition(session.dbKey);
		dimInfo.spawnPos = position.pos;
		dimInfo.spawnRotation = position.heading;
		connection.sendTo(session.sessionId, MessagePacket(
			format(`spawn of %s dimension is now %s`, dimension, position.pos)));
	}

	void onTeleport(CommandParams params)
	{
		import std.regex : matchFirst, regex;
		import std.conv : to;
		Session* session = sessions[params.source];
		if(session is null) return;
		auto position = db.get!ClientPosition(session.dbKey);

		vec3 pos;

		auto regex3 = regex(`(-?\d+)\W+(-?\d+)\W+(-?\d+)`, "m");
		auto captures3 = matchFirst(params.rawArgs, regex3);

		if (!captures3.empty)
		{
			pos.x = to!int(captures3[1]);
			pos.y = to!int(captures3[2]);
			pos.z = to!int(captures3[3]);
			return tpToPos(session, pos);
		}

		auto regex2 = regex(`(-?\d+)\W+(-?\d+)`, "m");
		auto captures2 = matchFirst(params.rawArgs, regex2);
		if (!captures2.empty)
		{
			pos.x = to!int(captures2[1]);
			pos.y = position.pos.y;
			pos.z = to!int(captures2[2]);
			return tpToPos(session, pos);
		}

		auto regex1 = regex(`[a-Z]+[_a-Z0-9]+`);
		auto captures1 = matchFirst(params.rawArgs, regex1);
		if (!captures1.empty)
		{
			string destName = to!string(captures1[1]);
			Session* destination = sessions[destName];
			if(destination is null)
			{
				connection.sendTo(params.source, MessagePacket(
					format(`Player "%s" is not online`, destName)));
				return;
			}
			return tpToPlayer(session, destination);
		}

		connection.sendTo(params.source, MessagePacket(
			`Wrong syntax: "tp <x> [<y>] <z>" | "tp <player>"`));
	}

	void tpToPos(Session* session, vec3 pos) {
		connection.sendTo(session.sessionId, MessagePacket(
			format("Teleporting to %s %s %s", pos.x, pos.y, pos.z)));
		auto position = db.get!ClientPosition(session.dbKey);

		position.pos = pos;
		++position.positionKey;
		connection.sendTo(session.sessionId, ClientPositionPacket(position.pos,
			position.heading, position.dimension, position.positionKey));
		updateObserverBox(session);
	}

	void tpToPlayer(Session* session, Session* destination) {
		connection.sendTo(session.sessionId, MessagePacket(
			format("Teleporting to %s", destination.name)));
		auto position = db.get!ClientPosition(session.dbKey);
		auto destposition = db.get!ClientPosition(destination.dbKey);

		position.pos = destposition.pos;
		++position.positionKey;
		connection.sendTo(session.sessionId, ClientPositionPacket(position.pos,
			position.heading, position.dimension, position.positionKey));
		updateObserverBox(session);
	}

	bool isLoggedIn(SessionId sessionId)
	{
		Session* session = sessions[sessionId];
		return session.isLoggedIn;
	}

	bool isSpawned(SessionId sessionId)
	{
		Session* session = sessions[sessionId];
		return isSpawned(session);
	}

	bool isSpawned(Session* session)
	{
		return session.isLoggedIn && db.has!SpawnedFlag(session.dbKey);
	}

	string[EntityId] clientNames()
	{
		string[EntityId] names;
		foreach(session; sessions.byValue) {
			if (session.isLoggedIn)
				names[session.dbKey] = session.name;
		}

		return names;
	}

	string clientName(SessionId sessionId)
	{
		auto cl = sessions[sessionId];
		return cl ? cl.name : format("%s", sessionId);
	}

	auto loggedInClients()
	{
		import std.algorithm : filter, map;
		return sessions.byValue.filter!(a=>a.isLoggedIn).map!(a=>a.sessionId);
	}

	private void setClientPosition(Session* session, vec3 pos, vec2 heading, ushort dimension)
	{
		auto position = db.get!ClientPosition(session.dbKey);
		position.pos = pos;
		position.heading = heading;
		position.dimension = dimension;
		++position.positionKey;
	}

	private void setClientDimension(Session* session, ushort dimension)
	{
		auto dimInfo = serverWorld.dimMan.getOrCreate(dimension);
		auto position = db.get!ClientPosition(session.dbKey);
		position.pos = dimInfo.spawnPos;
		position.heading = dimInfo.spawnRotation;
		position.dimension = dimension;
		++position.positionKey;
	}

	private void spawnClient(Session* session)
	{
		auto position = db.get!ClientPosition(session.dbKey);
		connection.sendTo(session.sessionId,
			ClientPositionPacket(
				position.pos,
				position.heading,
				position.dimension,
				position.positionKey));
		updateObserverBox(session);
	}

	private void handleClientConnected(ref ClientConnectedEvent event)
	{
		sessions.put(event.sessionId, SessionType.unknownClient);
	}

	private void handleClientDisconnected(ref ClientDisconnectedEvent event)
	{
		Session* session = sessions[event.sessionId];
		infof("%s %s disconnected", event.sessionId, session.name);

		db.remove!LoggedInFlag(session.dbKey);
		db.remove!SpawnedFlag(session.dbKey);

		connection.sendToAll(ClientLoggedOutPacket(session.dbKey));
		sessions.remove(event.sessionId);
	}

	private void changeDimensionCommand(CommandParams params)
	{
		import std.conv : to, ConvException;

		Session* session = sessions[params.source];
		if (isSpawned(session))
		{
			if (params.args.length > 1)
			{
				auto position = db.get!ClientPosition(session.dbKey);
				auto dim = to!DimensionId(params.args[1]);
				if (dim == position.dimension)
					return;

				position.dimension = dim;
				++position.positionKey;
				updateObserverBox(session);

				connection.sendTo(params.source, ClientPositionPacket(position.pos,
					position.heading, position.dimension, position.positionKey));
			}
		}
	}

	private void updateObserverBox(Session* session)
	{
		auto position = db.get!ClientPosition(session.dbKey);
		auto settings = db.get!ClientSettings(session.dbKey);
		if (isSpawned(session)) {
			serverWorld.chunkObserverManager.changeObserverBox(
				session.sessionId, position.chunk, settings.viewRadius);
		}
	}

	private void handleLoginPacket(ubyte[] packetData, SessionId sessionId)
	{
		auto packet = unpackPacket!LoginPacket(packetData);
		string name = packet.clientName;
		Session* session = sessions[sessionId];

		bool createdNew;
		EntityId clientId = db.getOrCreate(name, createdNew);

		if (createdNew)
		{
			infof("new client registered %s %s", clientId, name);
			db.set(clientId, ClientPosition(), ClientSettings());
		}
		else
		{
			if (db.has!ClientSessionInfo(clientId))
			{
				bool hasConflict(string name) {
					EntityId clientId = db.getIdForName(name);
					if (clientId == 0) return false;
					return db.has!ClientSessionInfo(clientId);
				}

				// already logged in
				infof("client with name %s is already logged in %s", name, clientId);
				string requestedName = name;
				name = db.resolveNameConflict(requestedName, &hasConflict);
				infof("Using '%s' instead of '%s'", name, requestedName);
				clientId = db.getOrCreate(name, createdNew);

				if (createdNew)
				{
					infof("new client registered %s %s", clientId, name);
					db.set(clientId, ClientPosition(), ClientSettings());
				}
			}
			infof("client logged in %s %s", clientId, name);
		}

		db.set(clientId, ClientSessionInfo(name, session.sessionId));
		db.set(clientId, LoggedInFlag());

		sessions.identifySession(session.sessionId, name, clientId);

		connection.sendTo(sessionId, SessionInfoPacket(session.dbKey, clientNames));
		connection.sendToAllExcept(sessionId, ClientLoggedInPacket(session.dbKey, name));

		evDispatcher.postEvent(ClientLoggedInEvent(clientId, createdNew));

		infof("%s %s logged in", sessionId, sessions[sessionId].name);
	}

	private void handleGameStartPacket(ubyte[] packetData, SessionId sessionId)
	{
		Session* session = sessions[sessionId];
		if (session.isLoggedIn)
		{
			auto position = db.get!ClientPosition(session.dbKey);
			db.set(session.dbKey, SpawnedFlag());
			spawnClient(session);
			connection.sendTo(sessionId, SpawnPacket());
		}
	}

	private void handleViewRadius(ubyte[] packetData, SessionId sessionId)
	{
		import std.algorithm : clamp;
		auto packet = unpackPacket!ViewRadiusPacket(packetData);
		Session* session = sessions[sessionId];
		if (session.isLoggedIn)
		{
			auto settings = db.get!ClientSettings(session.dbKey);
			settings.viewRadius = clamp(packet.viewRadius,
				MIN_VIEW_RADIUS, MAX_VIEW_RADIUS);
			updateObserverBox(session);
		}
	}

	private void handleClientPosition(ubyte[] packetData, SessionId sessionId)
	{
		Session* session = sessions[sessionId];
		if (isSpawned(session))
		{
			auto packet = unpackPacket!ClientPositionPacket(packetData);
			auto position = db.get!ClientPosition(session.dbKey);

			// reject stale position. Dimension already has changed.
			if (packet.positionKey != position.positionKey)
				return;

			position.pos = vec3(packet.pos);
			position.heading = vec2(packet.heading);
			updateObserverBox(session);
		}
	}
}
