/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.net.packets;

import netlib.connection;

void registerPackets(Connection c)
{
	// Server -> Client
	c.registerPacket!PacketMapPacket;
	c.registerPacket!LoginPacket;
	c.registerPacket!SessionInfoPacket;

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
