/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.net.packets;

import netlib.connection;

void registerPackets(Connection c)
{
	// Server -> Client
	c.registerPacket!PacketMapPacket;
	c.registerPacket!SessionInfoPacket;

	// Client -> Server
	c.registerPacket!LoginPacket;
	c.registerPacket!GameStartPacket;

	// Common
	c.registerPacket!MessagePacket;

	// Server -> Client
	c.registerPacket!ClientLoggedInPacket;
	c.registerPacket!ClientLoggedOutPacket;
}

struct PacketMapPacket
{
	string[] packetNames;
}

// client request
struct LoginPacket
{
	string clientName;
}

struct GameStartPacket
{
}

// server response
struct SessionInfoPacket
{
	ClientId yourId;
	string[ClientId] clientNames;
}

struct ClientLoggedInPacket
{
	ClientId clientId;
	string clientName;
}

struct ClientLoggedOutPacket
{
	ClientId clientId;
}

// sent from client with peer == 0 and from server with userId of sender.
struct MessagePacket
{
	ClientId clientId; // from. Set to 0 when sending from client
	string msg;
}
