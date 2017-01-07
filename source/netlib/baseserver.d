/**
Copyright: Copyright (c) 2014-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module netlib.baseserver;

import std.range;

import voxelman.log;
import cbor;
import derelict.enet.enet;
import netlib;

struct PeerStorage
{
	ENetPeer*[SessionId] peers;
	private SessionId _nextSessionId = 0;

	ENetPeer* opIndex(SessionId id)
	{
		return peers.get(id, null);
	}

	SessionId addClient(ENetPeer* peer)
	{
		SessionId id = nextPeerId;
		peers[id] = peer;
		return id;
	}

	void removeClient(SessionId id)
	{
		peers.remove(id);
	}

	size_t length()
	{
		return peers.length;
	}

	private SessionId nextPeerId() @property
	{
		return _nextSessionId++;
	}
}

struct ConnectionSettings
{
	ENetAddress* address;
	size_t maxPeers;
	size_t numChannels;
	uint incomingBandwidth;
	uint outgoingBandwidth;
}

abstract class BaseServer
{
	PeerStorage peerStorage;
	mixin PacketManagement!(false);
	mixin BaseConnection!();

	void start(ConnectionSettings settings, uint hostAddr, ushort port)
	{
		ENetAddress address;
		address.host = hostAddr;
		address.port = port;
		settings.address = &address;

		if (isRunning) stop();

		host = enet_host_create(settings.address,
			settings.maxPeers,
			settings.numChannels,
			settings.incomingBandwidth,
			settings.outgoingBandwidth);

		if (host is null)
		{
			error("An error occured while trying to create an ENet host");
			return;
		}

		isRunning = true;
	}

	void update()
	{
		if (!isRunning) return;
		ENetEvent event;
		while (enet_host_service(host, &event, 0) > 0)
		{
			final switch (event.type)
			{
				case ENET_EVENT_TYPE_NONE:
					break;
				case ENET_EVENT_TYPE_CONNECT:
					onConnect(event);
					break;
				case ENET_EVENT_TYPE_RECEIVE:
					onPacketReceived(event);
					break;
				case ENET_EVENT_TYPE_DISCONNECT:
					onDisconnect(event);
					break;
			}
		}
	}

	/// Disconnects all clients.
	void disconnectAll()
	{
		if (!isRunning) return;
		foreach(peer; peerStorage.peers.byValue)
		{
			enet_peer_disconnect(peer, 0);
		}
	}

	/// Sends packet to specified clients.
	void sendTo(R)(R clients, ubyte[] data, ubyte channel = 0)
		if ((isInputRange!R && is(ElementType!R : SessionId)) ||
			is(R : SessionId))
	{
		if (!isRunning) return;
		ENetPacket* packet = enet_packet_create(data.ptr, data.length,
				ENET_PACKET_FLAG_RELIABLE);
		sendTo(clients, packet, channel);
	}

	/// ditto
	void sendTo(R, P)(R clients, auto ref const(P) packet, ubyte channel = 0)
		if (((isInputRange!R && is(ElementType!R : SessionId)) ||
			is(R : SessionId)) &&
			is(P == struct))
	{
		sendTo(clients, createPacket(packet), channel);
	}

	/// ditto
	void sendTo(R)(R clients, ENetPacket* packet, ubyte channel = 0)
		if ((isInputRange!R && is(ElementType!R : SessionId)) ||
			is(R : SessionId))
	{
		if (!isRunning) return;
		static if (isInputRange!R)
		{
			foreach(sessionId; clients)
			{
				if (auto peer = peerStorage[sessionId])
					enet_peer_send(peer, channel, packet);
			}
		}
		else // single SessionId
		{
			if (auto peer = peerStorage[clients])
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
	void sendToAllExcept(P)(SessionId exceptClient, auto ref const(P) packet, ubyte channel = 0)
		if (is(P == struct))
	{
		sendToAllExcept(exceptClient, createPacket(packet), channel);
	}

	/// ditto
	void sendToAllExcept(SessionId exceptClient, ubyte[] data, ubyte channel = 0)
	{
		if (!isRunning) return;
		ENetPacket* packet = enet_packet_create(data.ptr, data.length,
					ENET_PACKET_FLAG_RELIABLE);
		sendToAllExcept(exceptClient, packet, channel);
	}

	/// ditto
	void sendToAllExcept(SessionId exceptClient, ENetPacket* packet, ubyte channel = 0)
	{
		if (!isRunning) return;
		foreach(sessionId, peer; peerStorage.peers)
		{
			if (sessionId != exceptClient && peer)
				enet_peer_send(peer, channel, packet);
		}
	}
}
