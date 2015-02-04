/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.server.serverplugin;

import std.stdio : writeln;

import derelict.enet.enet;

import plugin;
import plugin.pluginmanager;
import netlib.connection;
import netlib.baseserver;

import voxelman.packets;
import voxelman.config;
import voxelman.plugins.eventdispatcherplugin;
import voxelman.server.chunkman;
import voxelman.server.clientinfo;
import voxelman.server.events;

final class ServerConnection : BaseServer!ClientInfo{}

class ServerPlugin : IPlugin
{
private:
	PluginManager pluginman = new PluginManager;
	EventDispatcherPlugin evDispatcher = new EventDispatcherPlugin;
	bool isStopping;

public:
	ServerConnection connection;
	ChunkMan chunkMan;
	// IPlugin stuff
	override string name() @property { return "ServerPlugin"; }
	override string semver() @property { return "0.3.0"; }

	override void preInit()
	{
		connection.connectHandler = &onConnect;
		connection.disconnectHandler = &onDisconnect;

		chunkMan.init();

		registerPackets(connection);
		//connection.printPacketMap();

		connection.registerPacketHandler!LoginPacket(&handleLoginPacket);
		connection.registerPacketHandler!MessagePacket(&handleMessagePacket);
		connection.registerPacketHandler!ClientPositionPacket(&handleClientPosition);
		connection.registerPacketHandler!ViewRadiusPacket(&handleViewRadius);
	}

	override void init(IPluginManager pluginman)
	{
		evDispatcher.subscribeToEvent(&handleCommand);
	}

	override void postInit() { }

	this()
	{
		loadEnet();

		connection = new ServerConnection;
		chunkMan = ChunkMan(connection);
	}

	void run(string[] args)
	{
		pluginman.registerPlugin(this);
		pluginman.registerPlugin(evDispatcher);

		pluginman.initPlugins();
		writeln;

		ConnectionSettings settings = {null, 32, 2, 0, 0};
		connection.start(settings, ENET_HOST_ANY, CONNECT_PORT);

		// Main loop
		while (connection.isRunning)
		{
			connection.update(100);
			chunkMan.update();			
		}

		connection.stop();
	}

	string[ClientId] clientNames()
	{
		string[ClientId] names;
		foreach(id, client; connection.clientStorage.clients)
		{
			names[id] = client.name;
		}

		return names;
	}

	void handleCommand(CommandEvent event)
	{
		import std.algorithm : splitter;
		import std.string : format;
		
		if (event.command.length <= 1)
		{
			sendMessageTo(event.clientId, "Invalid command");
			return;
		}

		// Split without leading '/'
		auto splitted = event.command[1..$].splitter;
		string commName = splitted.front;
		splitted.popFront;

		if (commName == "stop")
		{
			isStopping = true;
			connection.disconnectAll();
		}
		else
			sendMessageTo(event.clientId, format("Unknown command %s", commName));
	}

	void sendMessageTo(ClientId clientId, string message, ClientId from = 0)
	{
		connection.sendTo(clientId, MessagePacket(from, message));
	}

	void spawnClient(ClientId clientId)
	{
		connection.sendTo(clientId, ClientPositionPacket(0,0,0));

	}

	void onConnect(ref ENetEvent event)
	{
		auto clientId = connection.clientStorage.addClient(event.peer);
		event.peer.data = cast(void*)clientId;
		enet_peer_timeout(event.peer, 0, 0, 2000);
		writefln("%s connected", clientId);
		evDispatcher.postEvent(new ClientConnectedEvent(clientId));
	}

	void onDisconnect(ref ENetEvent event)
	{
		ClientId clientId = cast(ClientId)event.peer.data;
		writefln("%s %s disconnected", clientId,
			connection.clientStorage[clientId].name);

		chunkMan.removeObserver(clientId);

		evDispatcher.postEvent(new ClientDisconnectedEvent(clientId));
		
		// Reset client's information
		event.peer.data = null;
		connection.clientStorage.removeClient(clientId);

		connection.sendToAll(ClientLoggedOutPacket(clientId));
		
		writefln("totalObservedChunks %s", chunkMan.totalObservedChunks);
	}

	void handleLoginPacket(ubyte[] packetData, ClientId clientId)
	{
		LoginPacket packet = unpackPacket!LoginPacket(packetData);
		ClientInfo* info = connection.clientStorage[clientId];
		info.name = packet.clientName;
		info.isLoggedIn = true;
		info.pos = START_POS;
		connection.sendTo(clientId, ClientPositionPacket(info.pos.x, info.pos.y, info.pos.z));

		writefln("%s %s logged in", clientId,
			connection.clientStorage[clientId].name);

		connection.sendTo(clientId, SessionInfoPacket(clientId, clientNames));
		connection.sendToAllExcept(clientId, ClientLoggedInPacket(clientId, packet.clientName));

		evDispatcher.postEvent(new ClientLoggedInEvent(clientId));
	}

	void handleMessagePacket(ubyte[] packetData, ClientId clientId)
	{
		import std.algorithm : startsWith;
		import std.string : strip;

		auto packet = unpackPacket!MessagePacket(packetData);
			
		packet.clientId = clientId;
		string strippedMsg = packet.msg.strip;
		
		if (strippedMsg.startsWith("/"))
		{
			auto commandEvent = new CommandEvent(clientId, strippedMsg);
			evDispatcher.postEvent(commandEvent);
			return;
		}
		
		connection.sendToAll(packet);
	}

	void handleClientPosition(ubyte[] packetData, ClientId clientId)
	{
		ClientInfo* clientInfo = connection.clientStorage[clientId];
		if (clientInfo.isLoggedIn)
		{
			auto packet = unpackPacket!ClientPositionPacket(packetData);
			//writefln("Received ClientPositionPacket(%s, %s, %s)",
			//	packet.x, packet.y, packet.z);

			clientInfo.pos = vec3(cast(float)packet.x, cast(float)packet.y, cast(float)packet.z);
			clientInfo.heading = vec2(packet.angleHor, packet.angleVert);
			chunkMan.updateObserverPosition(clientId);
			writefln("totalObservedChunks %s", chunkMan.totalObservedChunks);
		}
	}

	void handleViewRadius(ubyte[] packetData, ClientId clientId)
	{
		auto packet = unpackPacket!ViewRadiusPacket(packetData);
		writefln("Received ViewRadiusPacket(%s)", packet.viewRadius);
	}
}