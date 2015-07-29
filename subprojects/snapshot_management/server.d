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
	int position;
	int viewRadius;
	auto observedChunks() @property { return iota(position - viewRadius, position + viewRadius + 1); }
	void sendChunk(ChunkWorldPos pos, const ubyte[] chunkData){}
	void sendChanges(ChunkWorldPos pos, const BlockChange[]){}
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
	ChunkInMemoryStorage storage;
	ChunkFreeList* freeList;

	ChunkDataSnapshot[ChunkWorldPos] snapshots;
	BlockId[][ChunkWorldPos] writeBuffers;
	//Chunk[ChunkWorldPos] chunks;

	Set!ChunkWorldPos loadingChunks;
	Set!ChunkWorldPos unloadingChunks;

	BlockChange[][ChunkWorldPos] changes;
	Client*[][ChunkWorldPos] chunkObservers;

	void constructor()
	{
		freeList = new ChunkFreeList;
		storage.freeList = freeList;
		storage.onChunkLoadedHandlers ~= &onChunkLoaded;
	}

	void preUpdate(Client*[] clients) {
		// Advance time
		++currentTime;
	}

	void postUpdate(Client*[] clients) {
		// Logic

		// Load chunks. onChunkLoaded will be called
		storage.update();

		// Send changes to clients
		foreach(changes; changes.byKeyValue) {
			foreach(client; chunkObservers.get(changes.key, null)) {
				client.sendChanges(changes.key, changes.value);
			}
		}
		changes = null;

		// Move new snapshots into old list
		foreach(snapshot; writeBuffers.byKeyValue) {
			auto oldData = snapshot.key in snapshots;
			assert(oldData);
			freeList.deallocate(oldData.blocks);
			infof("Old snapshot[%s]: time %s", snapshot.key, currentTime);
			snapshots[snapshot.key] = ChunkDataSnapshot(snapshot.value, currentTime);
		}
		writeBuffers = null;

		// process remove queue
	}

	void saveWorld() {

	}

	void onChunkLoaded(ChunkWorldPos wpos, ChunkDataSnapshot snap) {
		assert(wpos !in snapshots, format("Chunk '%s' is already loaded", wpos));
		infof("LOAD #%s", wpos);
		snapshots[wpos] = snap;
		loadingChunks.remove(wpos);
		foreach(client; chunkObservers.get(wpos, null)) {
			client.sendChunk(wpos, snap.blocks);
		}
	}

	void onClientConnected(Client* client) {
		infof("CONN '%s'", client.name);
		addObserver(client);
	}

	void onClientDisconnected(Client* client) {
		infof("DISC '%s'", client.name);
		removeObserver(client);
	}

	void addObserver(Client* client) {
		foreach(int pos; client.observedChunks) {
			auto wpos = ChunkWorldPos(pos);
			chunkObservers[wpos] = chunkObservers.get(wpos, null) ~ client;
			infof(" OBSV #%s by '%s'", pos, client.name);
			loadChunk(wpos);
		}
	}

	void removeObserver(Client* client) {
		foreach(pos; client.observedChunks) {
			auto wpos = ChunkWorldPos(pos);
			auto observers = chunkObservers.get(wpos, null);
			observers = remove!((a) => a == client, SwapStrategy.unstable)(observers);
			chunkObservers[wpos] = observers;
			infof(" UNOB #%s by '%s'", pos, client.name);
			if (observers.empty)
				unloadChunk(wpos);
		}
	}

	bool setBlock(BlockWorldPos bwp, BlockId blockId) {
		auto blockPos = BlockChunkPos(bwp);
		auto chunkPos = ChunkWorldPos(bwp);
		BlockId[] blocks = getWSnap(chunkPos);
		if (blocks is null)
			return false;
		infof("  SETB #%s", chunkPos);
		blocks[blockPos.pos] = blockId;
		addChange(chunkPos, BlockChange(blockPos, blockId));
		return true;
	}

	BlockId getBlock(BlockWorldPos blockPos) {
		return 0;
	}

	void addChange(ChunkWorldPos cwp, BlockChange blockChange) {
		changes[cwp] = changes.get(cwp, null) ~ blockChange;
	}

	void loadChunk(ChunkWorldPos cwp) {
		if (cwp in snapshots || loadingChunks.contains(cwp))
			return;
		loadingChunks.put(cwp);
		storage.loadChunk(cwp);
	}

	void unloadChunk(ChunkWorldPos cwp) {
		storage.saveChunk(cwp, snapshots[cwp]);
		snapshots.remove(cwp);
	}

	BlockId[] getWSnap(ChunkWorldPos chunkWorldPos) {
		auto newSnapshot = writeBuffers.get(chunkWorldPos, null);
		if (newSnapshot is null) {
			infof("   SNAP #%s", chunkWorldPos);
			auto old = chunkWorldPos in snapshots;
			if (old is null)
				return null;
			newSnapshot = freeList.allocate();
			newSnapshot[] = old.blocks;
		}
		return newSnapshot;
	}
}
