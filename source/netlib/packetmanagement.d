/**
Copyright: Copyright (c) 2014-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module netlib.packetmanagement;

import cbor;
import voxelman.log;
import derelict.enet.enet;
import voxelman.container.hash.set;

void loadEnet()
{
	int err = enet_initialize();

	if (err != 0)
	{
		error("Error loading ENet library");
		return;
	}
	else
	{
		ENetVersion ever = enet_linked_version();
		infof("Loaded ENet library v%s.%s.%s",
			ENET_VERSION_GET_MAJOR(ever),
			ENET_VERSION_GET_MINOR(ever),
			ENET_VERSION_GET_PATCH(ever));
	}
}

// packetData must contain data with packet id stripped off.
P unpackPacket(P)(ubyte[] packetData)
{
	return decodeCborSingleDup!P(packetData);
}

P unpackPacketNoDup(P)(ubyte[] packetData)
{
	return decodeCborSingle!P(packetData);
}

//version = Packet_Sniffing;

struct PacketSniffer(bool client)
{
	private enum sideName = client ? "[CLIENT]" : "[SERVER]";
	HashSet!string disallowedPakets;

	void onPacketCreate(string name, ubyte[] packetData) {
		version (Packet_Sniffing) {
			if (name !in disallowedPakets)
				tracef(sideName ~ " create %s %(%02x%)", name, packetData);
		}
	}

	void onPacketHandle(string name, ubyte[] packetData) {
		version (Packet_Sniffing) {
			if (name !in disallowedPakets)
				tracef(sideName ~ " handle %s %(%02x%)", name, packetData);
		}
	}
}

mixin template PacketManagement(bool client)
{
	static if (client)
		alias PacketHandler = void delegate(ubyte[] packetData);
	else
		alias PacketHandler = void delegate(ubyte[] packetData, SessionId sessionId);

	PacketSniffer!client sniffer;

	static struct PacketInfo
	{
		string name;
		PacketHandler handler;
		size_t id;
	}

	// Used when handling packet based on its id.
	PacketInfo*[] packetArray;

	// Used to get packet id when sending packet.
	PacketInfo*[TypeInfo] packetMap;

	size_t packetId(P)()
	{
		return packetMap[typeid(P)].id;
	}

	string packetName(size_t packetId)
	{
		if (packetId >= packetArray.length) return "!UnknownPacket!";
		return packetArray[packetId].name;
	}

	void registerPacket(P)(PacketHandler handler = null, string packetName = P.stringof)
	{
		size_t newId = packetArray.length;
		PacketInfo* pinfo = new PacketInfo(packetName, handler, newId);
		packetArray ~= pinfo;
		assert(typeid(P) !in packetMap);
		packetMap[typeid(P)] = pinfo;
	}

	void registerPacketHandler(P)(PacketHandler handler)
	{
		import std.string : format;
		assert(typeid(P) in packetMap, format("Packet '%s' was not registered", typeid(P)));
		packetMap[typeid(P)].handler = handler;
	}

	bool handlePacket(size_t packetId, ubyte[] packetData, ENetPeer* peer)
	{
		if (packetId >= packetArray.length)
			return false; // invalid packet

		sniffer.onPacketHandle(packetArray[packetId].name, packetData);

		auto handler = packetArray[packetId].handler;
		if (handler is null)
			return false; // handler is not set

		static if (client) {
			handler(packetData);
		} else {
			auto sessionId = SessionId(cast(size_t)peer.data);
			handler(packetData, sessionId);
		}

		return true;
	}

	ubyte[] createPacket(P)(auto ref const(P) packet)
	{
		ubyte[] bufferTemp = buffer;
		size_t size;

		size_t pid = packetId!P;
		size = encodeCbor(bufferTemp[], pid);
		size += encodeCbor(bufferTemp[size..$], packet);
		sniffer.onPacketCreate(packetArray[pid].name, bufferTemp[0..size]);

		return bufferTemp[0..size];
	}

	string[] packetNames() @property
	{
		import std.algorithm : map;
		import std.array : array;
		return packetArray.map!(a => a.name).array;
	}

	void printPacketMap()
	{
		foreach(i, packetInfo; packetArray)
		{
			tracef("% 2s: %s", i, packetInfo.name);
		}
	}

	void shufflePackets()
	{
		import std.random;
		randomShuffle(packetArray[1..$]);
		foreach (i, packetInfo; packetArray)
			packetInfo.id = i;
	}
}
