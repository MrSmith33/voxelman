/**
Copyright: Copyright (c) 2015-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.net.packets;

import datadriven : EntityId;

void registerPackets(Connection)(Connection c)
{
	// Server -> Client
	c.registerPacket!PacketMapPacket;
	c.registerPacket!IdMapPacket;
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

struct IdMapPacket
{
	string mapName;
	string[] names;
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
	EntityId yourId;
	string[EntityId] clientNames;
}

struct ClientLoggedInPacket
{
	EntityId clientId;
	string clientName;
}

struct ClientLoggedOutPacket
{
	EntityId clientId;
}

enum MessageEndpoint
{
	chat,
	launcherConsole,
	integratedConsole,
}

// Where server should send command output depending on client input method
MessageEndpoint[4] commandSourceToMsgEndpoint = [
	MessageEndpoint.integratedConsole, // <= clientConsole,
	MessageEndpoint.chat,              // <= clientChat,
	MessageEndpoint.launcherConsole,   // <= clientLauncher,
	MessageEndpoint.integratedConsole  // <= localLauncher, shouldn't happen
];

// sent from client with peer == 0 and from server with userId of sender.
struct MessagePacket
{
	string msg;
	EntityId clientId; // from. Set to 0 when sending from client
	MessageEndpoint endpoint; // Where message came from (if from client), or should be sent to (if to client)
}
