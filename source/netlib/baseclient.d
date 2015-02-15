/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module netlib.baseclient;

import core.thread;
import std.conv : to;
import std.stdio : writefln, writeln;
import std.string : format, toStringz;

import derelict.enet.enet;

import netlib.connection;

abstract class BaseClient : Connection
{
	ENetAddress serverAddress;
	ENetPeer* server;

	void connect(string address, ushort port)
	{
		enet_address_set_host(&serverAddress, address.toStringz);
		serverAddress.port = port;

		server = enet_host_connect(host, &serverAddress, 2, 42);
		//enet_peer_timeout(server, 0, 0, 5000);

		if (server is null)
		{
			writeln("An error occured while trying to create an ENet server peer");
			return;
		}
	}

	void disconnect()
	{
		enet_peer_disconnect(server, 0);
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
		send(createPacket(packet), channel);
	}
}