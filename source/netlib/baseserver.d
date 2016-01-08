/**
Copyright: Copyright (c) 2014-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module netlib.baseserver;

import std.range;

import derelict.enet.enet;

import netlib.connection;
import netlib.clientstorage;

abstract class BaseServer : Connection
{
	ClientStorage clientStorage;

	void start(ConnectionSettings settings, uint host, ushort port)
	{
		ENetAddress address;
		address.host = host;
		address.port = port;
		settings.address = &address;

		super.start(settings);
	}

	/// Disconnects all clients.
	void disconnectAll()
	{
		if (!isRunning) return;
		foreach(peer; clientStorage.clientPeers.byValue)
		{
			enet_peer_disconnect(peer, 0);
		}
	}

	/// Sends packet to specified clients.
	void sendTo(R)(R clients, ubyte[] data, ubyte channel = 0)
		if ((isInputRange!R && is(ElementType!R : ClientId)) ||
			is(R : ClientId))
	{
		if (!isRunning) return;
		ENetPacket* packet = enet_packet_create(data.ptr, data.length,
				ENET_PACKET_FLAG_RELIABLE);
		sendTo(clients, packet, channel);
	}

	/// ditto
	void sendTo(R, P)(R clients, auto ref const(P) packet, ubyte channel = 0)
		if (((isInputRange!R && is(ElementType!R : ClientId)) ||
			is(R : ClientId)) &&
			is(P == struct))
	{
		sendTo(clients, createPacket(packet), channel);
	}

	/// ditto
	void sendTo(R)(R clients, ENetPacket* packet, ubyte channel = 0)
		if ((isInputRange!R && is(ElementType!R : ClientId)) ||
			is(R : ClientId))
	{
		if (!isRunning) return;
		static if (isInputRange!R)
		{
			foreach(clientId; clients)
			{
				if (auto peer = clientStorage[clientId])
					enet_peer_send(peer, channel, packet);
			}
		}
		else // single ClientId
		{
			if (auto peer = clientStorage[clients])
				enet_peer_send(peer, channel, packet);
		}
	}

	/// Sends packet to all clients.
	void sendToAll(P)(auto ref P packet, ubyte channel = 0)
		if (is(P == struct))
	{
		sendToAll(createPacket(packet), channel);
	}

	/// ditto
	void sendToAll(ubyte[] data, ubyte channel = 0)
	{
		if (!isRunning) return;
		ENetPacket* packet = enet_packet_create(data.ptr, data.length,
					ENET_PACKET_FLAG_RELIABLE);
		sendToAll(packet, channel);
	}

	/// ditto
	void sendToAll(ENetPacket* packet, ubyte channel = 0)
	{
		if (!isRunning) return;
		enet_host_broadcast(host, channel, packet);
	}

	/// Sends packet to all clients except one.
	void sendToAllExcept(P)(ClientId exceptClient, auto ref const(P) packet, ubyte channel = 0)
		if (is(P == struct))
	{
		sendToAllExcept(exceptClient, createPacket(packet), channel);
	}

	/// ditto
	void sendToAllExcept(ClientId exceptClient, ubyte[] data, ubyte channel = 0)
	{
		if (!isRunning) return;
		ENetPacket* packet = enet_packet_create(data.ptr, data.length,
					ENET_PACKET_FLAG_RELIABLE);
		sendToAllExcept(exceptClient, packet, channel);
	}

	/// ditto
	void sendToAllExcept(ClientId exceptClient, ENetPacket* packet, ubyte channel = 0)
	{
		if (!isRunning) return;
		foreach(clientId, peer; clientStorage.clientPeers)
		{
			if (clientId != exceptClient && peer)
				enet_peer_send(peer, channel, packet);
		}
	}
}
