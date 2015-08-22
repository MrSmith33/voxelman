/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module storage;

import std.algorithm : map, joiner;
import std.experimental.logger;
import std.string;
import std.typecons : Nullable;
import std.conv : to;
import server;
import chunkmanager : ChunkManager;
import voxelman.utils.queue;
import voxelman.storage.utils;

// Storage made to test delays in read and write.
struct ChunkInMemoryStorage {
	void delegate(ChunkWorldPos, ChunkDataSnapshot)[] onChunkLoadedHandlers;
	void delegate(ChunkWorldPos, ChunkDataSnapshot)[] onChunkSavedHandlers;

	private static struct SaveItem {
		ChunkWorldPos cwp;
		ChunkDataSnapshot snapshot;
	}
	private static struct LoadItem {
		ChunkWorldPos cwp;
		BlockId[] blockBuffer;
	}
	private ChunkDataSnapshot[ChunkWorldPos] snapshots;
	private Queue!LoadItem snapshotsToLoad;
	private Queue!SaveItem snapshotsToSave;

	// load one chunk per update
	void update() {
		auto toLoad = snapshotsToLoad.valueRange;
		if (!toLoad.empty) {
			LoadItem loadItem = toLoad.front;
			toLoad.popFront();
			ChunkDataSnapshot snap = snapshots.get(loadItem.cwp, ChunkDataSnapshot());
			if (snap.blocks) {
				loadItem.blockBuffer[] = snap.blocks;
			}
			snap.blocks = loadItem.blockBuffer;

			foreach(handler; onChunkLoadedHandlers)
				handler(loadItem.cwp, snap);
		}

		auto toSave = snapshotsToSave.valueRange;
		if (!toSave.empty) {
			SaveItem saveItem = toSave.front;
			toSave.popFront();
			ChunkDataSnapshot* snap = saveItem.cwp in snapshots;
			if (snap) {
				snap.blocks[] = saveItem.snapshot.blocks;
				saveItem.snapshot.blocks = snap.blocks;
			} else {
				saveItem.snapshot.blocks = saveItem.snapshot.blocks.dup;
			}
			ChunkWorldPos cwp = saveItem.cwp;
			snapshots[cwp] = saveItem.snapshot;
			foreach(handler; onChunkSavedHandlers)
				handler(cwp, saveItem.snapshot);
		}
	}

	// duplicate queries aren't checked.
	void loadChunk(ChunkWorldPos cwp, BlockId[] blockBuffer) {
		snapshotsToLoad.put(LoadItem(cwp, blockBuffer));
	}

	void saveChunk(ChunkWorldPos cwp, ChunkDataSnapshot snapshot) {
		snapshotsToSave.put(SaveItem(cwp, snapshot));
	}
}

final class WorldAccess {
	private ChunkManager* chunkManager;

	this(ChunkManager* chunkManager) {
		this.chunkManager = chunkManager;
	}

	bool setBlock(BlockWorldPos bwp, BlockId blockId) {
		auto blockPos = BlockChunkPos(bwp);
		auto chunkPos = ChunkWorldPos(bwp);
		BlockId[] blocks = chunkManager.getWriteBuffer(chunkPos);
		if (blocks is null)
			return false;
		infof("  SETB @%s", chunkPos);
		blocks[blockPos.pos] = blockId;

		import std.range : only;
		chunkManager.onBlockChanges(chunkPos, only(BlockChange(blockPos, blockId)));
		return true;
	}

	BlockId getBlock(BlockWorldPos bwp) {
		auto blockPos = BlockChunkPos(bwp);
		auto chunkPos = ChunkWorldPos(bwp);
		auto snap = chunkManager.getChunkSnapshot(chunkPos);
		if (!snap.isNull) {
			return snap.blocks[blockPos.pos];
		}
		return 0;
	}
}

struct Volume1D {
	int position;
	int size;

	bool empty() @property const {
		return size == 0;
	}

	bool contains(int otherPosition) const {
		if (otherPosition < position || otherPosition >= position + size) return false;
		return true;
	}

	bool opEquals()(auto ref const Volume1D other) const {
		return position == other.position && size == other.size;
	}

	// generates all positions within volume.
	auto positions() @property const {
		import std.range : iota;
		return iota(position, position + size);
	}
}

// Manages lists of observers per chunk
final class ChunkObserverManager {
	void delegate(ChunkWorldPos, size_t numObservers) changeChunkNumObservers;

	private ChunkObservers[ChunkWorldPos] chunkObservers;
	private Volume1D[ClientId] viewVolumes;

	ClientId[] getChunkObservers(ChunkWorldPos cwp) {
		if (auto observers = cwp in chunkObservers)
			return observers.clients;
		else
			return null;
	}

	void addServerObserver(ChunkWorldPos cwp) {
		auto list = chunkObservers.get(cwp, ChunkObservers.init);
		++list.numServerObservers;
		changeChunkNumObservers(cwp, list.numObservers);
		chunkObservers[cwp] = list;
	}

	void removeServerObserver(ChunkWorldPos cwp) {
		auto list = chunkObservers.get(cwp, ChunkObservers.init);
		--list.numServerObservers;
		changeChunkNumObservers(cwp, list.numObservers);
		if (list.empty)
			chunkObservers.remove(cwp);
		else
			chunkObservers[cwp] = list;
	}

	void addObserver(ClientId clientId, Volume1D volume) {
		assert(clientId !in viewVolumes, "Client is already added");
		changeObserverVolume(clientId, volume);
	}

	void removeObserver(ClientId clientId) {
		if (clientId in viewVolumes) {
			changeObserverVolume(clientId, Volume1D.init);
			viewVolumes.remove(clientId);
		}
		else
			warningf("removing observer %s, that was not added", clientId);
	}

	void changeObserverVolume(ClientId clientId, Volume1D newVolume) {
		Volume1D oldVolume = viewVolumes.get(clientId, Volume1D.init);
		viewVolumes[clientId] = newVolume;

		TrisectAxisResult tsect = trisectAxis(oldVolume.position, oldVolume.position + oldVolume.size,
			newVolume.position, newVolume.position + newVolume.size);

		// remove observer
		foreach(a; tsect.aranges[0..tsect.numRangesA]
		.map!(a => Volume1D(a.start, a.length).positions).joiner) {
			removeChunkObserver(ChunkWorldPos(a), clientId);
		}

		// add observer
		foreach(b; tsect.branges[0..tsect.numRangesB]
		.map!(b => Volume1D(b.start, b.length).positions).joiner) {
			addChunkObserver(ChunkWorldPos(b), clientId);
		}
	}

	private void addChunkObserver(ChunkWorldPos cwp, ClientId clientId) {
		auto list = chunkObservers.get(cwp, ChunkObservers.init);
		list.add(clientId);
		changeChunkNumObservers(cwp, list.numObservers);
		chunkObservers[cwp] = list;
		infof(" OBSV @%s by '%s'", cwp, clientId);
	}

	private void removeChunkObserver(ChunkWorldPos cwp, ClientId clientId) {
		auto list = chunkObservers.get(cwp, ChunkObservers.init);
		list.remove(clientId);
		changeChunkNumObservers(cwp, list.numObservers);
		if (list.empty)
			chunkObservers.remove(cwp);
		else
			chunkObservers[cwp] = list;
		infof(" UNOB @%s by '%s'", cwp, clientId);
	}
}

// Describes observers for a single chunk
struct ChunkObservers {
	// clients observing this chunk
	private ClientId[] _clients;
	// ref counts for keeping chunk loaded
	size_t numServerObservers;

	ClientId[] clients() @property {
		return _clients;
	}

	bool empty() @property const {
		return numObservers == 0;
	}

	size_t numObservers() @property const {
		return _clients.length + numServerObservers;
	}

	void add(ClientId clientId) {
		_clients ~= clientId;
	}

	void remove(ClientId clientId) {
		import std.algorithm : remove, SwapStrategy;
		_clients = remove!((a) => a == clientId, SwapStrategy.unstable)(_clients);
	}
}
