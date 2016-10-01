/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.core.packets;

import netlib.connection;
import voxelman.math;
import voxelman.world.storage.worldbox : WorldBox;

void registerPackets(Connection c)
{
	// Common
	c.registerPacket!ClientPositionPacket;
	c.registerPacket!FillBlockBoxPacket;
	c.registerPacket!PlaceBlockEntityPacket;
	c.registerPacket!RemoveBlockEntityPacket;

	// Server -> Client
	c.registerPacket!ChunkDataPacket;
	c.registerPacket!SpawnPacket;
	c.registerPacket!MultiblockChangePacket;

	// Client -> Server
	c.registerPacket!ViewRadiusPacket;
	c.registerPacket!CommandPacket;
}

// sent by client when position/heading changes.
struct ClientPositionPacket
{
	import voxelman.core.config : DimensionId;
	float[3] pos = [0, 0, 0];
	float[2] heading = [0, 0];
	DimensionId dimension;
	ubyte positionKey;
}

// sent by client after receiving SessionInfoPacket
struct ViewRadiusPacket
{
	int viewRadius;
}

struct ChunkDataPacket
{
	import voxelman.world.storage.chunk : BlockData;
	int[4] chunkPos;
	BlockData[] layers;
}

struct MultiblockChangePacket
{
	import voxelman.world.storage.chunk : BlockChange;
	int[4] chunkPos;
	BlockChange[] blockChanges;
}

struct FillBlockBoxPacket
{
	import voxelman.core.config : BlockId;
	WorldBox box;
	BlockId blockId;
}

struct PlaceBlockEntityPacket
{
	WorldBox box;
	ulong data;
}

struct RemoveBlockEntityPacket
{
	int[4] blockPos;
}

struct SpawnPacket
{
}

struct CommandPacket
{
	string command;
}
