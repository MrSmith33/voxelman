/**
Copyright: Copyright (c) 2014-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module netlib.baseclient;

import core.thread;
import std.conv : to;
import std.string : toStringz;
import std.experimental.logger;

import derelict.enet.enet;

import netlib.connection;

abstract class BaseClient : Connection
{
	ENetAddress serverAddress;
	ENetPeer* server;
	bool isConnecting;

	void connect(string address, ushort port)
	{
		enet_address_set_host(&serverAddress, address.toStringz);
		serverAddress.port = port;

		server = enet_host_connect(host, &serverAddress, 2, 42);
		//enet_peer_timeout(server, 0, 0, 5000);

		if (server is null)
		{
			error("An error occured while trying to create an ENet server peer");
			return;
		}

		isConnecting = true;
	}

	bool isConnected() @property
	{
		return host.connectedPeers > 0;
	}

	void disconnect()
	{
		if (isConnecting)
			enet_peer_disconnect_now(server, 0);
		else
			enet_peer_disconnect(server, 0);
		isConnecting = false;
	}

	void send(ubyte[] data, ubyte channel = 0)
	{
		ENetPacket* packet = enet_packet_create(data.ptr, data.length,
				ENET_PACKET_FLAG_RELIABLE);
		enet_peer_send(server, channel, packet);
	}

	void send(P)(auto ref const(P) packet, ubyte channel = 0)
		if (is(P == struct))
	{
		if (packetId!P >= packetArray.length)
		{
			infof("Dropping packet %s: %s", P.stringof, packetId!P);
			return;
		}

		send(createPacket(packet), channel);
	}

	// Set id mapping for packets
	void setPacketMap(string[] packetNames)
	{
		import std.algorithm : countUntil, remove, SwapStrategy;

		PacketInfo*[] newPacketArray;
		newPacketArray.reserve(packetNames.length);

		static bool pred(PacketInfo* packetInfo, string packetName)
		{
			return packetInfo.name == packetName;
		}

		foreach(i, packetName; packetNames)
		{
			ptrdiff_t index = countUntil!pred(packetArray, packetName);
			size_t newId = newPacketArray.length;

			if (index > -1)
			{
				newPacketArray ~= packetArray[index];
				remove!(SwapStrategy.unstable)(packetArray, index);
			}
			else
			{
				newPacketArray ~= new PacketInfo(packetName);
			}
			newPacketArray[$-1].id = newId;
		}

		packetArray = newPacketArray;
	}

	override void update()
	{
		ENetEvent event;
		while (enet_host_service(host, &event, 0) > 0)
		{
			final switch (event.type)
			{
				case ENET_EVENT_TYPE_NONE:
					break;
				case ENET_EVENT_TYPE_CONNECT:
					isConnecting = false;
					onConnect(event);
					break;
				case ENET_EVENT_TYPE_RECEIVE:
					onPacketReceived(event);
					break;
				case ENET_EVENT_TYPE_DISCONNECT:
					onDisconnect(event);
					isConnecting = false;
					break;
			}
		}
	}
}
