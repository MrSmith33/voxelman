/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.server.app;

import std.stdio : writeln;

import derelict.enet.enet;

import modular;
import modular.modulemanager;
import netlib.connection : ClientId, ConnectionSettings, loadEnet, unpackPacket;

import voxelman.packets : registerPackets, MessagePacket;
import voxelman.modules.eventdispatchermodule;
import voxelman.server.server : Server;
import voxelman.server.events : CommandEvent, scoped;

class ServerApp : IModule
{
private:
	ModuleManager moduleman = new ModuleManager;
	EventDispatcherModule evDispatcher = new EventDispatcherModule;
	bool isStopping;

public:
	Server server;
	// IModule stuff
	override string name() @property { return "ServerApp"; }
	override string semver() @property { return "1.0.0"; }
	override void preInit() { }
	override void init(IModuleManager moduleman)
	{
		evDispatcher.subscribeToEvent(&handleCommand);
	}
	override void postInit() { }

	void run(string[] args)
	{
		loadEnet();

		server = new Server(evDispatcher);

		registerPackets(server);

		server.registerPacketHandler!MessagePacket(&handleMessagePacket);
		server.registerPacketHandlers();

		moduleman.registerModule(this);
		moduleman.registerModule(evDispatcher);

		moduleman.initModules();
		writeln;

		ConnectionSettings settings = {null, 32, 2, 0, 0};
		server.start(settings, ENET_HOST_ANY, 1234);

		// Main loop
		while (server.isRunning)
		{
			server.update(100);
		}

		server.stop();
	}

	void handleMessagePacket(ubyte[] packetData, ClientId clientId)
	{
		import std.algorithm : startsWith;
		import std.string : strip;

		MessagePacket packet = unpackPacket!MessagePacket(packetData);
			
		packet.clientId = clientId;
		string strippedMsg = packet.msg.strip;
		
		if (strippedMsg.startsWith("/"))
		{
			auto commandEvent = new CommandEvent(clientId, strippedMsg);
			evDispatcher.postEvent(commandEvent);
			return;
		}
		
		server.sendToAll(packet);
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
			server.disconnectAll();
		}
		else
			sendMessageTo(event.clientId, format("Unknown command %s", commName));
	}

	void sendMessageTo(ClientId clientId, string message, ClientId from = 0)
	{
		server.sendTo(clientId, MessagePacket(from, message));
	}
}