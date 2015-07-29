/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module server;

import std.experimental.logger;
import std.array;
import std.algorithm;
import std.exception;
import std.range;
import std.math;
import std.conv;
import std.string;

import storage;

alias Timestamp = uint;
alias BlockId = ubyte;
alias ClientId = uint;

// 1D version of engine for test
enum CHUNK_SIZE = 16;

struct HashSet(K) {
	private void[0][K] set;

	void put()(auto ref K key) {
		set[key] = (void[0]).init;
	}

	bool remove()(auto ref K key) {
        return set.remove(key);
    }

    size_t length() const @property {
        return set.length;
    }

    @property bool empty() const {
        return set.length == 0;
    }

    bool opCast(T: bool)() const {
        return !empty;
    }

    bool opBinaryRight(string op)(auto ref K key) const if(op == "in") {
        return cast(bool)(key in set);
    }

    void clear() {
    	set = null;
    }

    auto items() @property {
    	return set.byKey;
    }
}

struct BlockWorldPos {
	this(int blockWorldPos){
		pos = blockWorldPos;
	}
	this(float blockWorldPos) {
		pos = cast(int)blockWorldPos;
	}
	int pos;
	string toString() @safe {return to!string(pos);}
}

struct BlockChunkPos {
	this(BlockWorldPos blockWorldPos) {
		int ipos = blockWorldPos.pos % CHUNK_SIZE;
		if (ipos < 0) ipos += CHUNK_SIZE;
		pos = cast(ubyte)ipos;
	}
	this(ubyte blockChunkPos) {
		pos = blockChunkPos;
	}
	ubyte pos;
	string toString() @safe {return to!string(pos);}
}

// Position of chunk in world space. -int.max..int.max
struct ChunkWorldPos {
	this(BlockWorldPos blockWorldPos) {
		pos = cast(int)floor(cast(float)blockWorldPos.pos / CHUNK_SIZE);
	}
	this(int chunkWorldPos) {
		pos = chunkWorldPos;
	}
	int pos;
	string toString() @safe {return to!string(pos);}
}

struct BlockChange {
	BlockChunkPos index;
	BlockId blockId;
}

struct ChunkDataSnapshot {
	BlockId[] blocks;
	Timestamp timestamp;
	uint numUsers;
}

struct Client {
	string name;
	ClientId id;
	Volume1D viewVolume;
	void sendChunk(ChunkWorldPos pos, const ubyte[] chunkData){}
	void sendChanges(ChunkWorldPos cwp, BlockChange[] changes){
		infof("changes #%s %s", cwp, changes);
	}
	void delegate(Server* server) sendDataToServer;
}

struct ChunkFreeList {
	BlockId[][] items;
	size_t numItems;

	BlockId[] allocate() {
		if (numItems > 0) {
			--numItems;
			return items[numItems];
		} else {
			return new BlockId[CHUNK_SIZE];
		}
	}

	void deallocate(BlockId[] blocks) {
		if (items.length < numItems) {
			items[numItems] = blocks;
		} else {
			items.reserve(32);
			items ~= blocks;
		}
	}
}

struct Set(T) {
	T[] items;
	alias items this;

	bool contains(T item) {
		return canFind(items, item);
	}

	// returns true if already has one
	bool put(T item) {
		if (!contains(item)) {
			items ~= item;
			return false;
		} else
			return true;
	}

	void remove(T item) {
		T[] items;
		items = std.algorithm.remove!(a => a == item, SwapStrategy.unstable)(items);
	}
}

struct Server {
	Timestamp currentTime;
	SnapshotProvider snapshotProvider;
	ChunkManager chunkManager;
	ChunkObserverManager chunkObserverManager;
	WorldAccess worldAccess;

	Client*[ClientId] clientMap;

	void constructor()
	{
		snapshotProvider.constructor();
		chunkManager.constructor(&snapshotProvider);
		chunkManager.onChunkLoadedHandlers ~= &onChunkLoaded;
		chunkManager.chunkChangesHandlers ~= &sendChanges;
		worldAccess.constructor(&chunkManager);
		chunkObserverManager.changeChunkNumObservers = &chunkManager.changeChunkNumObservers;
	}

	void preUpdate() {
		// Advance time
		++currentTime;
		snapshotProvider.update();
	}

	void update() {
		// logic. modify world, modify observers
	}

	void postUpdate() {
		chunkManager.postUpdate(currentTime);

		// do regular save
		// chunkManager.save(currentTime);
	}

	void save() {
		chunkManager.save(currentTime);
	}

	void sendChanges(ChunkWorldPos cwp, BlockChange[] changes) {
		foreach(clientId; chunkObserverManager.getChunkObservers(cwp)) {
			clientMap[clientId].sendChanges(cwp, changes);
		}
	}

	void onChunkLoaded(ChunkWorldPos cwp, ChunkDataSnapshot snap) {
		infof("LOAD #%s", cwp);
		foreach(clientId; chunkObserverManager.getChunkObservers(cwp)) {
			clientMap[clientId].sendChunk(cwp, snap.blocks);
		}
	}

	void onClientConnected(Client* client) {
		infof("CONN '%s'", client.name);
		clientMap[client.id] = client;
		chunkObserverManager.addObserver(client.id, client.viewVolume);
	}

	void onClientDisconnected(Client* client) {
		infof("DISC '%s'", client.name);
		chunkObserverManager.removeObserver(client.id);
	}

	bool setBlock(BlockWorldPos bwp, BlockId blockId) {
		return worldAccess.setBlock(bwp, blockId);
	}

	BlockId getBlock(BlockWorldPos bwp) {
		return worldAccess.getBlock(bwp);
	}
}
