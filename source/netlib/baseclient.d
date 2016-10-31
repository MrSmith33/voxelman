/**
Copyright: Copyright (c) 2014-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module netlib.baseclient;

import cbor;
import core.thread;
import std.conv : to;
import std.string : toStringz;
import voxelman.log;

import derelict.enet.enet;

import netlib;

abstract class BaseClient
{
	mixin PacketManagement!(true);
	mixin BaseConnection!();

	ENetAddress serverAddress;
	ENetPeer* server;
	bool isConnecting;
	bool isConnected;

	void start(ConnectionSettings settings)
	{
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

	void connect(string address, ushort port)
	{
		ENetAddress addr;
		enet_address_set_host(&addr, address.toStringz);
		addr.port = port;

		if (isConnecting)
		{
			if (addr == serverAddress)
			{
				return;
			}
			else
			{
				disconnect();
			}
		}
		serverAddress = addr;
		connect();
	}

	void connect()
	{
		server = enet_host_connect(host, &serverAddress, 2, 42);
		//enet_peer_timeout(server, 0, 0, 5000);

		if (server is null)
		{
			error("An error occured while trying to create an ENet server peer");
			return;
		}

		isConnecting = true;
	}

	void disconnect()
	{
		if (isConnecting)
		{
			enet_peer_disconnect_now(server, 0);
			isConnecting = false;
		}
		else
		{
			enet_peer_disconnect(server, 0);
		}
	}

	void send(ubyte[] data, ubyte channel = 0)
	{
		if (!isRunning) return;
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

	void update()
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
					isConnected = true;
					onConnect(event);
					break;
				case ENET_EVENT_TYPE_RECEIVE:
					onPacketReceived(event);
					break;
				case ENET_EVENT_TYPE_DISCONNECT:
					onDisconnect(event);
					isConnecting = false;
					isConnected = false;
					break;
			}
		}
	}
}
