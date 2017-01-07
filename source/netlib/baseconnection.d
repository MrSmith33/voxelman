/**
Copyright: Copyright (c) 2014-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module netlib.baseconnection;

import derelict.enet.enet;
import netlib;
import cbor;

mixin template BaseConnection()
{
	bool isRunning;

	// Local side of connection.
	ENetHost* host;

	ubyte[] buffer = new ubyte[1024*1024];

	void delegate(ref ENetEvent) connectHandler;
	void delegate(ref ENetEvent) disconnectHandler;

	void flush()
	{
		if (!isRunning) return;
		enet_host_flush(host);
	}

	void stop()
	{
		isRunning = false;
		enet_host_destroy(host);
	}

	void onConnect(ref ENetEvent event)
	{
		if (connectHandler) connectHandler(event);
	}

	void onPacketReceived(ref ENetEvent event)
	{
		ubyte[] packetData = event.packet.data[0..event.packet.dataLength];
		auto fullPacketData = packetData;
		size_t packetId;

		try
		{
			// decodes and pops ulong from range.
			packetId = cast(size_t)decodeCborSingle!ulong(packetData);

			handlePacket(packetId, packetData, event.peer);
		}
		catch(CborException e)
		{
			import std.conv : to;
			error(e.to!string);
			errorf("packet:%s length:%s data:%(%x%)", packetName(packetId), event.packet.dataLength, fullPacketData);
			printCborStream(fullPacketData);
		}
	}

	void onDisconnect(ref ENetEvent event)
	{
		if (disconnectHandler) disconnectHandler(event);
	}
}
