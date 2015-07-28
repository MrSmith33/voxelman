/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module server2;

import std.experimental.logger;
import std.array;
import std.algorithm;
import std.exception;
import std.range;
import std.math;
import std.conv;
import std.string;

import storage;
import server;


struct Server {
	Timestamp currentTime;

	SnapshotProvider snapshotProvider;
	ChunkManager chunkManager;
	WorldAccess worldAccess;
	ChunkObserverManager chunkObserverMan;

	void constructor()
	{
		freeList = new ChunkFreeList;

		snapshotProvider.constructor(freeList);
		snapshotProvider.onSnapshotLoadedHandlers ~= &chunkManager.onChunkLoaded;
		snapshotProvider.onSnapshotSavedHandlers ~= &chunkManager.onSnapshotSaved;

		storage.freeList = freeList;
		storage.onChunkLoadedHandlers ~= &onChunkLoaded;
		chunkObserverMan.changeChunkNumObservers = &chunkManager.changeChunkNumObservers;

	}

	void preUpdate(Client*[] clients) {
		// Advance time
		++currentTime;
	}

	void update() {
		snapshotProvider.update();
	}

	void postUpdate(Client*[] clients) {
		chunkManager.postUpdate();

		// Load chunks. onChunkLoaded will be called
		storage.update();
	}
}
