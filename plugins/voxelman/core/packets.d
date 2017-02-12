/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.core.packets;

import netlib;
import voxelman.math;
import voxelman.core.config : DimensionId;
import voxelman.world.storage.worldbox : WorldBox;
import voxelman.world.storage.coordinates : ClientDimPos;

void registerPackets(Connection)(Connection c)
{
	// Common
	c.registerPacket!ClientPositionPacket;
	c.registerPacket!FillBlockBoxPacket;
	c.registerPacket!PlaceBlockEntityPacket;
	c.registerPacket!RemoveBlockEntityPacket;

	// Server -> Client
	c.registerPacket!ChunkDataPacket;
	c.registerPacket!DimensionInfoPacket;
	c.registerPacket!SpawnPacket;
	c.registerPacket!MultiblockChangePacket;

	// Client -> Server
	c.registerPacket!ViewRadiusPacket;
	c.registerPacket!CommandPacket;
}

// sent by client when position/heading changes.
struct ClientPositionPacket
{
	ClientDimPos dimPos;
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
	import voxelman.world.storage.chunk : ChunkLayerData;
	ivec4 chunkPos;
	ChunkLayerData[] layers;
}

struct DimensionInfoPacket
{
	DimensionId dimension;
	Box borders;
}

struct MultiblockChangePacket
{
	import voxelman.world.storage.chunk : BlockChange;
	ivec4 chunkPos;
	BlockChange[] blockChanges;
}

struct FillBlockBoxPacket
{
	import voxelman.core.config : BlockId, BlockMetadata;
	WorldBox box;
	BlockId blockId;
	BlockMetadata blockMeta;
}

struct PlaceBlockEntityPacket
{
	WorldBox box;
	ulong data;
}

struct RemoveBlockEntityPacket
{
	ivec4 blockPos;
}

struct SpawnPacket
{
}

struct CommandPacket
{
	string command;
}
