/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module netlib.baseserver;

import std.stdio;
import std.range;

import derelict.enet.enet;

import netlib.connection;
import netlib.clientstorage;

abstract class BaseServer(Client) : Connection
{
	ClientStorage!Client clientStorage;
	
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
		foreach(user; clientStorage.clients.byValue)
		{
			enet_peer_disconnect(user.peer, 0);
		}
	}

	/// Sends packet to specified clients.
	void sendTo(R)(R clients, ubyte[] data, ubyte channel = 0)
		if ((isInputRange!R && is(ElementType!R : ClientId)) ||
			is(R : ClientId))
	{
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
		static if (isInputRange!R)
		{
			foreach(clientId; clients)
			{
				if (auto client = clientStorage[clientId])
					enet_peer_send(client.peer, channel, packet);
			}
		}
		else
		{
			if (auto client = clientStorage[clients])
					enet_peer_send(client.peer, channel, packet);
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
		ENetPacket* packet = enet_packet_create(data.ptr, data.length,
					ENET_PACKET_FLAG_RELIABLE);
		sendToAll(packet, channel);
	}

	/// ditto
	void sendToAll(ENetPacket* packet, ubyte channel = 0)
	{
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
		ENetPacket* packet = enet_packet_create(data.ptr, data.length,
					ENET_PACKET_FLAG_RELIABLE);
		sendToAllExcept(exceptClient, packet, channel);
	}

	/// ditto
	void sendToAllExcept(ClientId exceptClient, ENetPacket* packet, ubyte channel = 0)
	{
		foreach(clientId, client; clientStorage.clients)
		{
			if (clientId != exceptClient && client)
				enet_peer_send(client.peer, channel, packet);
		}
	}
}