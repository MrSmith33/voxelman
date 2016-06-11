/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.core.packets;

import netlib.connection;
import dlib.math.vector;

void registerPackets(Connection c)
{
	// Common
	c.registerPacket!ClientPositionPacket;
	c.registerPacket!FillBlockVolumePacket;

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
	import voxelman.core.config : DimentionId;
	vec3 pos = vec3(0, 0, 0);
	vec2 heading = vec2(0, 0);
	DimentionId dimention;
}

// sent by client after receiving SessionInfoPacket
struct ViewRadiusPacket
{
	int viewRadius;
}

struct ChunkDataPacket
{
	import voxelman.world.storage.chunk : BlockData;
	ivec4 chunkPos;
	BlockData blockData;
}

struct MultiblockChangePacket
{
	import voxelman.world.storage.chunk : BlockChange;
	ivec4 chunkPos;
	BlockChange[] blockChanges;
}

struct FillBlockVolumePacket
{
	import voxelman.world.storage.volume : Volume;
	import voxelman.core.config : BlockId;
	Volume volume;
	BlockId blockId;
}

struct SpawnPacket
{
}

struct CommandPacket
{
	string command;
}
