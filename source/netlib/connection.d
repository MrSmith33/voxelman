/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module netlib.connection;

import std.stdio;

import derelict.enet.enet;
import cbor;

void loadEnet()
{
	DerelictENet.load();

	int err = enet_initialize();

	if (err != 0)
	{
		writefln("Error loading ENet library");
		return;
	}
	else
	{
		ENetVersion ever = enet_linked_version();
		writefln("Loaded ENet library v%s.%s.%s",
			ENET_VERSION_GET_MAJOR(ever),
			ENET_VERSION_GET_MINOR(ever),
			ENET_VERSION_GET_PATCH(ever));
	}
}

// Client id type. Used in server to identify clients.
alias ClientId = size_t;

/// Packet handler.
/// Returns true if data was valid and false otherwise.
alias PacketHandler = void delegate(ubyte[] packetData, ClientId clientId);

struct PacketInfo
{
	string name;
	PacketHandler handler;
	TypeInfo packetType;
	size_t id;
}

struct ConnectionSettings
{
	ENetAddress* address;
	size_t maxPeers;
	size_t numChannels;
	uint incomingBandwidth;
	uint outgoingBandwidth;
}

// packetData must contain data with packet id stripped off.
P unpackPacket(P)(ubyte[] packetData)
{
	return decodeCborSingleDup!P(packetData);
}

abstract class Connection
{
	// True if connection is still open.
	bool isRunning;

	// Local side of connection.
	ENetHost* host;

	// Used when handling packet based on its id.
	PacketInfo*[] packetArray;
	// Used to get packet id when sending packet.
	PacketInfo*[TypeInfo] packetMap;

	ubyte[] buffer = new ubyte[1024*1024];

	void delegate() connectHandler;
	void delegate() disconnectHandler;

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
			writeln("An error occured while trying to create an ENet host");
			return;
		}

		isRunning = true;
	}

	size_t packetId(P)()
	{
		return packetMap[typeid(P)].id;
	}

	string packetName(size_t packetId)
	{
		if (packetId >= packetArray.length) return "!Unknown!";
		return packetArray[packetId].name;
	}

	void registerPacket(P)(PacketHandler handler = null, string packetName = P.stringof)
	{
		size_t newId = packetArray.length;
		PacketInfo* pinfo = new PacketInfo(packetName, handler, typeid(P), newId);
		packetArray ~= pinfo;
		assert(typeid(P) !in packetMap);
		packetMap[typeid(P)] = pinfo;
	}

	void registerPacketHandler(P)(PacketHandler handler)
	{
		assert(typeid(P) in packetMap);
		packetMap[typeid(P)].handler = handler;
	}

	bool handlePacket(size_t packetId, ubyte[] packetData, ClientId peerInfo)
	{
		if (packetId >= packetArray.length)
			return false; // invalid packet

		auto handler = packetArray[packetId].handler;
		if (handler is null)
			return false; // handler is not set

		handler(packetData, peerInfo);
		return true;
	}

	ubyte[] createPacket(P)(auto ref const(P) packet)
	{
		ubyte[] bufferTemp = buffer;
		size_t size;

		size = encodeCbor(bufferTemp[], packetId!P);
		size += encodeCbor(bufferTemp[size..$], packet);

		return bufferTemp[0..size];
	}

	void printPacketMap()
	{
		foreach(i, packetInfo; packetArray)
		{
			writefln("% 2s: %s", i, packetInfo.name);
		}
	}

	void flush()
	{
		enet_host_flush(host);
	}

	void stop()
	{
		enet_host_destroy(host);
	}

	void update(uint msecs)
	{
		ENetEvent event;
		int eventStatus = enet_host_service(host, &event, msecs);

		if (eventStatus == 0) return;

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

	void onConnect(ref ENetEvent event)
	{
		if (connectHandler) connectHandler();
	}

	void onPacketReceived(ref ENetEvent event)
	{
		try
		{
			ubyte[] packetData = event.packet.data[0..event.packet.dataLength];
			auto fullPacketData = packetData;
			// decodes and pops ulong from range.
			size_t packetId = cast(size_t)decodeCborSingle!ulong(packetData);

			handlePacket(packetId, packetData, cast(ClientId)event.peer.data);
		}
		catch(CborException e)
		{
			writeln(e);
		}
	}

	void onDisconnect(ref ENetEvent event)
	{
		if (disconnectHandler) disconnectHandler();
	}
}