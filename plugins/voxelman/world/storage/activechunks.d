/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.activechunks;

import voxelman.log;
import std.array : empty;
import cbor;
import voxelman.container.hashset;

import voxelman.world.storage;

struct ActiveChunks
{
	private auto dbKey = IoKey("voxelman.world.active_chunks");
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
		foreach(cwp; chunks) {
			loadChunk(cwp);
			infof("load active: %s", cwp);
		}
	}

	package(voxelman.world) void read(ref PluginDataLoader loader) {
		ubyte[] data = loader.readEntryRaw(dbKey);
		if (!data.empty) {
			auto token = decodeCborToken(data);
			assert(token.type == CborTokenType.arrayHeader);
			foreach(_; 0..token.uinteger)
				chunks.put(decodeCborSingle!ChunkWorldPos(data));
			assert(data.empty);
		}
	}

	package(voxelman.world) void write(ref PluginDataSaver saver) {
		auto sink = saver.beginWrite();
		encodeCborArrayHeader(sink, chunks.length);
		foreach(cwp; chunks)
			encodeCbor(sink, cwp);
		saver.endWrite(dbKey);
	}
}
