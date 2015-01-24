/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.packets;

import netlib.connection;
import dlib.math.vector : ivec3;
import voxelman.chunk : ChunkData;

void registerPackets(Connection c)
{
	// Common
	c.registerPacket!MessagePacket;
	
	// Server -> Client
	c.registerPacket!LoginPacket;
	c.registerPacket!SessionInfoPacket;
	c.registerPacket!ClientLoggedInPacket;
	c.registerPacket!ClientLoggedOutPacket;

	c.registerPacket!ChunkDataPacket;
	
	// Client -> Server
	c.registerPacket!ChunkRequestPacket;
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

struct ChunkRequestPacket
{
	ivec3 chunkPos;
}

struct ChunkDataPacket
{
	ivec3 chunkPos;
	ChunkData chunkData;
}