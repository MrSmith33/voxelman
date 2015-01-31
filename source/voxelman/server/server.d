/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.server.server;

import derelict.enet.enet;
import netlib.connection;
import netlib.baseserver;

import voxelman.packets;
import voxelman.modules.eventdispatchermodule;
import voxelman.server.events;
import voxelman.server.clientinfo;

class Server : BaseServer!ClientInfo
{
private:
	EventDispatcherModule evDispatcher;

public:
	this(EventDispatcherModule evDispatcher)
	{
		this.evDispatcher = evDispatcher;
	}

	string[ClientId] clientNames()
	{
		string[ClientId] names;
		foreach(id, client; clientStorage.clients)
		{
			names[id] = client.name;
		}

		return names;
	}

	void registerPacketHandlers()
	{
		registerPacketHandler!LoginPacket(&handleLoginPacket);
	}

	override void onConnect(ref ENetEvent event)
	{
		auto clientId = clientStorage.addClient(event.peer);
		event.peer.data = cast(void*)clientId;
		enet_peer_timeout(event.peer, 0, 0, 2000);

		auto _event = new ClientConnectedEvent(clientId);
		evDispatcher.postEvent(_event);
	}

	override void onDisconnect(ref ENetEvent event)
	{
		ClientId clientId = cast(ClientId)event.peer.data;
		
		clientStorage.removeClient(clientId);

		sendToAll(ClientLoggedOutPacket(clientId));

		// Reset client's information
		event.peer.data = null;

		auto _event = new ClientDisconnectedEvent(clientId);
		evDispatcher.postEvent(_event);
	}

	void handleLoginPacket(ubyte[] packetData, ClientId clientId)
	{
		LoginPacket packet = unpackPacket!LoginPacket(packetData);
		
		clientStorage[clientId].name = packet.clientName;
		
		sendTo(clientId, SessionInfoPacket(clientId, clientNames));
		sendToAllExcept(clientId, ClientLoggedInPacket(clientId, packet.clientName));

		auto _event = new ClientLoggedInEvent(clientId);
		evDispatcher.postEvent(_event);
	}
}