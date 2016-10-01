/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.activechunks;

import std.experimental.logger;
import std.array : empty;
import cbor;
import voxelman.container.hashset;

import voxelman.world.storage.coordinates;
import voxelman.world.storage.plugindata;

struct ActiveChunks
{
	private immutable string dbKey = "voxelman.world.active_chunks";
	HashSet!ChunkWorldPos chunks;
	void delegate(ChunkWorldPos cwp) loadChunk;
	void delegate(ChunkWorldPos cwp) unloadChunk;

	void add(ChunkWorldPos cwp) {
		chunks.put(cwp);
		loadChunk(cwp);
	}

	void remove(ChunkWorldPos cwp) {
		if (chunks.remove(cwp))
			unloadChunk(cwp);
	}

	void loadActiveChunks() {
		foreach(cwp; chunks.items) {
			loadChunk(cwp);
			infof("load active: %s", cwp);
		}
	}

	package(voxelman.world) void read(ref PluginDataLoader loader) {
		ubyte[] data = loader.readWorldEntry(dbKey);
		if (!data.empty) {
			auto token = decodeCborToken(data);
			assert(token.type == CborTokenType.arrayHeader);
			foreach(_; 0..token.uinteger)
				chunks.put(decodeCborSingle!ChunkWorldPos(data));
			assert(data.empty);
		}
	}

	package(voxelman.world) void write(ref PluginDataSaver saver) {
		auto sink = saver.tempBuffer;
		size_t encodedSize = encodeCborArrayHeader(sink[], chunks.length);
		foreach(cwp; chunks.items)
			encodedSize += encodeCbor(sink[encodedSize..$], cwp);
		saver.writeWorldEntry(dbKey, encodedSize);
	}
}
