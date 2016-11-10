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


struct ClientPositionManager
{
	ClientManager cm;

	void tpToPos(Session* session, ClientDimPos dimPos, DimensionId dim)
	{
		auto position = cm.db.get!ClientPosition(session.dbKey);

		position.dimPos = dimPos;
		position.dimension = dim;
		++position.positionKey;

		sendPositionToClient(*position, session.sessionId);
		updateObserverBox(session);
	}

	void tpToPlayer(Session* session, Session* destination)
	{
		cm.connection.sendTo(session.sessionId, MessagePacket(
			format("Teleporting to %s", destination.name)));
		auto position = cm.db.get!ClientPosition(session.dbKey);
		auto destposition = cm.db.get!ClientPosition(destination.dbKey);

		position.dimPos = destposition.dimPos;
		position.dimension = destposition.dimension;
		++position.positionKey;

		sendPositionToClient(*position, session.sessionId);
		updateObserverBox(session);
	}

	void updateClientViewRadius(
		Session* session,
		int viewRadius)
	{
		auto settings = cm.db.get!ClientSettings(session.dbKey);
		settings.viewRadius = clamp(viewRadius,
			MIN_VIEW_RADIUS, MAX_VIEW_RADIUS);
		updateObserverBox(session);
	}

	// Set client postion on server side, without sending position update to client
	void updateClientPosition(
		Session* session,
		ClientDimPos dimPos,
		ushort dimension,
		ubyte positionKey,
		bool updatePositionKey,
		bool sendPosUpdate = false)
	{
		auto position = cm.db.get!ClientPosition(session.dbKey);

		// reject stale position. Dimension already has changed.
		if (position.positionKey != positionKey)
			return;

		position.dimPos = dimPos;
		position.dimension = dimension;
		position.positionKey += cast(ubyte)updatePositionKey;

		if(sendPosUpdate)
			sendPositionToClient(*position, session.sessionId);

		updateObserverBox(session);
	}

	void tpToDimension(Session* session, DimensionId dimension)
	{
		auto dimInfo = cm.serverWorld.dimMan.getOrCreate(dimension);
		auto position = cm.db.get!ClientPosition(session.dbKey);
		position.dimPos = dimInfo.spawnPos;
		position.dimension = dimension;
		++position.positionKey;

		sendPositionToClient(*position, session.sessionId);
		updateObserverBox(session);
	}

	private void sendPositionToClient(ClientPosition position, SessionId sessionId)
	{
		cm.serverWorld.dimObserverMan.updateObserver(sessionId, position.dimension);
		cm.connection.sendTo(sessionId,
			ClientPositionPacket(
				position.dimPos,
				position.dimension,
				position.positionKey));
	}

	// updates WorldBox of observer in ChunkObserverManager
	// must be called after new position was sent to client.
	// ChunkObserverManager can initiate chunk sending when observed
	// box changes.
	private void updateObserverBox(Session* session)
	{
		if (cm.isSpawned(session)) {
			auto position = cm.db.get!ClientPosition(session.dbKey);
			auto settings = cm.db.get!ClientSettings(session.dbKey);
			auto borders = cm.serverWorld.dimMan.dimensionBorders(position.dimension);
			cm.serverWorld.chunkObserverManager.changeObserverBox(
				session.sessionId, position.chunk, settings.viewRadius, borders);
		}
	}
}

immutable vec3[string] dirToVec;
static this()
{
	dirToVec = [
		"u" : vec3( 0, 1, 0),
		"d" : vec3( 0,-1, 0),
		"l" : vec3(-1, 0, 0),
		"r" : vec3( 1, 0, 0),
		"f" : vec3( 0, 0,-1),
		"b" : vec3( 0, 0, 1),
		];
}

final class ClientManager : IPlugin
{
private:
	EventDispatcherPlugin evDispatcher;
	NetServerPlugin connection;
	ServerWorld serverWorld;

public:
	ClientDb db;
	SessionManager sessions;
	ClientPositionManager clientPosMan;

	// IPlugin stuff
	mixin IdAndSemverFrom!"voxelman.session.plugininfo";

	this() {
		clientPosMan.cm = this;
	}

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
			setWorldSpawn(position.dimension, session);
			return;
		}

		clientPosMan.tpToPos(
			session, serverWorld.worldInfo.spawnPos,
			serverWorld.worldInfo.spawnDimension);
	}

	void setWorldSpawn(DimensionId dimension, Session* session)
	{
		auto position = db.get!ClientPosition(session.dbKey);
		serverWorld.worldInfo.spawnPos = position.dimPos;
		serverWorld.worldInfo.spawnDimension = dimension;
		connection.sendTo(session.sessionId, MessagePacket(
			format(`world spawn is now dim %s pos %s`, dimension, position.dimPos.pos)));
	}

	void setDimensionSpawn(DimensionId dimension, Session* session)
	{
		auto dimInfo = serverWorld.dimMan.getOrCreate(dimension);
		auto position = db.get!ClientPosition(session.dbKey);
		dimInfo.spawnPos = position.dimPos;
		connection.sendTo(session.sessionId, MessagePacket(
			format(`spawn of %s dimension is now %s`, dimension, position.dimPos.pos)));
	}

	void onTeleport(CommandParams params)
	{
		import std.regex : matchFirst, regex;
		import std.conv : to;
		Session* session = sessions[params.source];
		if(session is null) return;
		auto position = db.get!ClientPosition(session.dbKey);

		vec3 pos;

		// tp <x> <y> <z>
		auto regex3 = regex(`(-?\d+)\W+(-?\d+)\W+(-?\d+)`, "m");
		auto captures3 = matchFirst(params.rawArgs, regex3);

		if (!captures3.empty)
		{
			pos.x = to!int(captures3[1]);
			pos.y = to!int(captures3[2]);
			pos.z = to!int(captures3[3]);
			connection.sendTo(session.sessionId, MessagePacket(
				format("Teleporting to %s %s %s", pos.x, pos.y, pos.z)));
			clientPosMan.tpToPos(session, ClientDimPos(pos), position.dimension);
			return;
		}

		// tp u|d|l|r|f|b \d+
		auto regexDir = regex(`([udlrfb])\W+(-?\d+)`, "m");
		auto capturesDir = matchFirst(params.rawArgs, regexDir);

		if (!capturesDir.empty)
		{
			string dir = capturesDir[1];
			if (auto dirVector = dir in dirToVec)
			{
				int delta = to!int(capturesDir[2]);
				pos = position.dimPos.pos + *dirVector * delta;
				connection.sendTo(session.sessionId, MessagePacket(
					format("Teleporting to %s %s %s", pos.x, pos.y, pos.z)));
				clientPosMan.tpToPos(session, ClientDimPos(pos), position.dimension);
				return;
			}
		}

		// tp <x> <z>
		auto regex2 = regex(`(-?\d+)\W+(-?\d+)`, "m");
		auto captures2 = matchFirst(params.rawArgs, regex2);
		if (!captures2.empty)
		{
			pos.x = to!int(captures2[1]);
			pos.y = position.dimPos.pos.y;
			pos.z = to!int(captures2[2]);
			clientPosMan.tpToPos(session, ClientDimPos(pos), position.dimension);
			return;
		}

		// tp <player>
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
			clientPosMan.tpToPlayer(session, destination);
			return;
		}

		connection.sendTo(params.source, MessagePacket(
			`Wrong syntax: "tp <x> [<y>] <z>" | "tp <player>" | "tp u|d|l|r|f|b <num_blocks>"`));
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

	private void handleClientConnected(ref ClientConnectedEvent event)
	{
		sessions.put(event.sessionId, SessionType.unknownClient);
	}

	private void handleClientDisconnected(ref ClientDisconnectedEvent event)
	{
		Session* session = sessions[event.sessionId];
		infof("%s %s disconnected", event.sessionId, session.name);

		db.remove!LoggedInFlag(session.dbKey);
		db.remove!ClientSessionInfo(session.dbKey);
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

				clientPosMan.tpToDimension(session, dim);
			}
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
			clientPosMan.sendPositionToClient(*position, session.sessionId);
			db.set(session.dbKey, SpawnedFlag());
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
			clientPosMan.updateClientViewRadius(session, packet.viewRadius);
		}
	}

	private void handleClientPosition(ubyte[] packetData, SessionId sessionId)
	{
		Session* session = sessions[sessionId];
		if (isSpawned(session))
		{
			auto packet = unpackPacket!ClientPositionPacket(packetData);

			clientPosMan.updateClientPosition(
				session, packet.dimPos, packet.dimension,
				packet.positionKey, false);
		}
	}
}
