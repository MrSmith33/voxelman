/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module storage;

import std.algorithm : map, joiner;
import std.experimental.logger;
import std.string;
import server;
import voxelman.utils.queue;
import voxelman.storage.utils;


struct ChunkInMemoryStorage {
	ChunkFreeList* freeList;
	void delegate(ChunkWorldPos, ChunkDataSnapshot)[] onChunkLoadedHandlers;
	void delegate(ChunkWorldPos)[] onChunkSavedHandlers;

	private static struct SaveItem {
		ChunkWorldPos cwp;
		ChunkDataSnapshot snapshot;
	}
	private ChunkDataSnapshot[ChunkWorldPos] snapshots;
	private Queue!ChunkWorldPos snapshotsToLoad;
	private Queue!SaveItem snapshotsToSave;

	// load one chunk per update
	void update() {
		auto toLoad = snapshotsToLoad.valueRange;
		if (!toLoad.empty) {
			ChunkWorldPos chunkWorldPos = toLoad.front;
			toLoad.popFront();
			ChunkDataSnapshot snap = snapshots.get(chunkWorldPos, ChunkDataSnapshot(freeList.allocate()));
			foreach(handler; onChunkLoadedHandlers)
				handler(chunkWorldPos, snap);
		}

		auto toSave = snapshotsToSave.valueRange;
		if (!toSave.empty) {
			SaveItem saveItem = toSave.front;
			toSave.popFront();
			ChunkDataSnapshot* snap = saveItem.cwp in snapshots;
			if (snap) {
				freeList.deallocate(snap.blocks);
			}
			ChunkWorldPos cwp = saveItem.cwp;
			snapshots[cwp] = saveItem.snapshot;
			infof("UNLD #%s", cwp);
			foreach(handler; onChunkSavedHandlers)
				handler(cwp);
		}
	}

	// duplicate queries aren't checked.
	void loadChunk(ChunkWorldPos pos) {
		snapshotsToLoad.put(pos);
	}

	void saveChunk(ChunkWorldPos pos, ChunkDataSnapshot snapshot) {
		snapshotsToSave.put(SaveItem(pos, snapshot));
	}
}

// TODO: add delay to snap unload and send message back on snap unload to free mem

struct SnapshotProvider {
	void delegate(ChunkWorldPos, ChunkDataSnapshot)[] onSnapshotLoadedHandlers;
	void delegate(ChunkWorldPos)[] onSnapshotSavedHandlers;

	private HashSet!ChunkWorldPos loadingSnapshots;
	private HashSet!ChunkWorldPos unloadingSnapshots;
	private HashSet!ChunkWorldPos loadedSnapshots;
	private ChunkInMemoryStorage inMemoryStorage; // replaced with IO thread in real case. Simulates delay of IO

	void constructor() {
		inMemoryStorage.onChunkLoadedHandlers ~= &onSnapshotLoaded;
		inMemoryStorage.onChunkSavedHandlers ~= &onSnapshotSaved;
	}

	void update() {
		inMemoryStorage.update();
	}

	void loadChunk(ChunkWorldPos cwp) {
		if (cwp in unloadingSnapshots) {
			unloadingSnapshots.remove(cwp);
			// if was loading then it will continue
		} else if (cwp !in loadingSnapshots){
			loadingSnapshots.put(cwp);
			// send buffer to IO thread
			inMemoryStorage.loadChunk(cwp);
		} else {
			// is loading already
			// do nothing
		}
	}

	// called if chunk was loaded before and needs to be saved
	void saveChunk(ChunkWorldPos cwp, ChunkDataSnapshot snapshot) {
		unloadingSnapshots.put(cwp);
		// can't be loading
		assert(cwp !in loadingSnapshots);
		assert(cwp in loadedSnapshots);
		// send buffer and position to IO thread
		inMemoryStorage.saveChunk(cwp, snapshot);
		loadedSnapshots.remove(cwp);
	}

	private void onSnapshotLoaded(ChunkWorldPos cwp, ChunkDataSnapshot snapshot) {
		loadedSnapshots.put(cwp);
		foreach(handler; onSnapshotLoadedHandlers)
			handler(cwp, snapshot);
	}

	private void onSnapshotSaved(ChunkWorldPos cwp) {
		foreach(handler; onSnapshotSavedHandlers)
			handler(cwp);
	}
}
/*
struct SnapshotStorage {
	private ChunkDataSnapshot*[ChunkWorldPos] snapshots;
	private Timestamp[ChunkWorldPos] loadedSnapshots;
	private Set!ChunkDataSnapshot snapshotsInUse;
	private ChunkFreeList* freeList;



	void unloadUnusedSnapshots() {
		size_t i = 0;
		while (i < snapshotsInUse.length) {
			if (snapshotsInUse[i].numReaders == 0) {
				freeList.deallocate(snapshotsInUse[i].blocks);
				snapshotsInUse[i] = snapshotsInUse[$-1];
				snapshotsInUse.length -= 1;
			} else {
				++i;
			}
		}
	}
}*/

enum ChunkState {
	state_0,
	state_3,
	state_9,
	state_11,
	state_12,
	state_14,
}

struct ChunkManager {
	void delegate(ChunkWorldPos cwp)[] onChunkAddedHandlers;
	void delegate(ChunkWorldPos cwp)[] onChunkRemovedHandlers;
	void delegate(ChunkWorldPos cwp)[] onChunkLoadedHandlers;

	ChunkFreeList* freeList;
	private SnapshotProvider* snapshotProvider;
	//private Timestamp[ChunkWorldPos] savedTimestamps;
	private ChunkDataSnapshot[ChunkWorldPos] snapshots;
	private ChunkDataSnapshot[][ChunkWorldPos] oldSnapshots;
	private HashSet!ChunkWorldPos addedChunks;
	private HashSet!ChunkWorldPos loadingChunks;
	private BlockId[][ChunkWorldPos] writeBuffers;
	private BlockChange[][ChunkWorldPos] chunkChanges;
	private ChunkState[ChunkWorldPos] chunkStates;

	void constructor() {
	}

	void loadChunk(ChunkWorldPos cwp) {
		auto state = chunkStates.get(cwp, ChunkState.state_0);
		with(ChunkState) final switch(state) {
			case state_0:
				chunkStates[cwp] = state_14;
				snapshotProvider.loadChunk(cwp);
				loadingChunks.put(cwp);
				addChunk(cwp);
				break;
			case state_3:
				break; // ignore
			case state_9:
				chunkStates[cwp] = state_11;
				addChunk(cwp);
			case state_11:
				break; // ignore
			case state_12:
				chunkStates[cwp] = state_14;
				addChunk(cwp);
			case state_14:
				break; // ignore
		}


		// ignore for states 3, 11, 14
		if (cwp in addedChunks) return;
		if (cwp !in snapshots && cwp in loadingChunks) {
			// state 0
			snapshotProvider.loadChunk(cwp);
			loadingChunks.put(cwp);
		} // else ignore loading for states 9, 12, but add

		addChunk(cwp);
	}

	private void addChunk(ChunkWorldPos cwp) {
		addedChunks.put(cwp);
		foreach(handler; onChunkAddedHandlers)
			handler(cwp);
	}

	void unloadChunk(ChunkWorldPos cwp) {
		if (cwp !in addedChunks) return;
		addedChunks.remove(cwp);
		auto snap = getChunkSnapshot(cwp);
		if (snap != ChunkDataSnapshot.init) {
			snapshotProvider.saveChunk(cwp, snap);
		}
		foreach(handler; onChunkRemovedHandlers)
			handler(cwp);
	}

	void save(Timestamp currentTime) {

	}

	void postUpdate(Timestamp currentTime) {
		commitSnapshots(currentTime);
		sendChanges();
	}

	// Chunk storage ---------------------------------------

	void setChunkSnapshot(ChunkWorldPos chunkWorldPos, BlockId[] blocks, Timestamp currentTime) {
		auto oldData = getChunkSnapshot(chunkWorldPos);
		if (oldData) {
			freeList.deallocate(oldData.blocks);
		}
		infof("Old snapshot[%s]: time %s", chunkWorldPos, currentTime);
		snapshots[chunkWorldPos] = ChunkDataSnapshot(blocks, currentTime);
	}

	// returns ChunkDataSnapshot.init if has no snapshot
	ChunkDataSnapshot getChunkSnapshot(ChunkWorldPos chunkWorldPos) {
		return snapshots.get(chunkWorldPos, ChunkDataSnapshot.init);
	}

	// Chunk write management ------------------------------

	// copies old snapshot data and returns it
	BlockId[] getWriteBuffer(ChunkWorldPos chunkWorldPos) {
		auto newData = writeBuffers.get(chunkWorldPos, null);
		if (newData is null) {
			infof("   SNAP #%s", chunkWorldPos);
			auto old = getChunkSnapshot(chunkWorldPos);
			if (old is ChunkDataSnapshot.init)
				return null;
			newData = freeList.allocate();
			newData[] = old.blocks;
		}
		return newData;
	}

	private void clearWriteBuffers() {
		writeBuffers = null;
	}

	// Chunk change management -----------------------------

	void onBlockChange(ChunkWorldPos cwp, BlockChange blockChange) {
		changes[cwp] = changes.get(cwp, null) ~ blockChange;
	}

	private void clearChunkChanges() {
		chunkChanges = null;
	}

	// -----------------------------------------------------

	// called at the end of tick
	private void commitSnapshots(Timestamp currentTime) {
		foreach(snapshot; writeBuffers.byKeyValue) {
			setChunkSnapshot(snapshot.key, snapshot.value, currentTime);
		}
		clearWriteBuffers();
	}

	private void changeChunkNumObservers(ChunkWorldPos cwp, size_t numObservers) {
		if (numObservers > 0) {
			loadChunk(cwp);
		} else {
			unloadChunk(cwp);
		}
	}

	private void onSnapshotLoaded(ChunkWorldPos cwp, ChunkDataSnapshot snap) {
		setChunkSnapshot(cwp, snapshot.blocks, currentTimesnap.timestamp);
		foreach(handler; onChunkLoadedHandlers)
			handler(cwp);
	}

	private void onSnapshotSaved(ChunkWorldPos cwp, ChunkDataSnapshot snap) {

	}

	// Send changes to clients
	private void sendChanges() {
		foreach(changes; chunkChanges.byKeyValue) {
			//infof() send chunk changes
			//sendToChunkObservers(changes.key,
			//	MultiblockChangePacket(changes.key, changes.value));
		}
		clearChunkChanges();
	}
}

struct WorldAccess {
	private ChunkManager* chunkManager;

	bool setBlock(BlockWorldPos bwp, BlockId blockId) {
		auto blockPos = BlockChunkPos(bwp);
		auto chunkPos = ChunkWorldPos(bwp);
		BlockId[] blocks = chunkManager.getWriteBuffer(chunkPos);
		if (blocks is null)
			return false;
		infof("  SETB #%s", chunkPos);
		blocks[blockPos.pos] = blockId;
		chunkManager.onBlockChange(chunkPos, BlockChange(blockPos, blockId));
		return true;
	}

	BlockId getBlock(BlockWorldPos bwp) {
		auto blockPos = BlockChunkPos(bwp);
		auto chunkPos = ChunkWorldPos(bwp);
		auto snap = chunkManager.getChunkSnapshot(chunkPos);
		if (snap) {
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
struct ChunkObserverManager {
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
	}

	private void removeChunkObserver(ChunkWorldPos cwp, ClientId clientId) {
		auto list = chunkObservers.get(cwp, ChunkObservers.init);
		list.remove(clientId);
		changeChunkNumObservers(cwp, list.numObservers);
		if (list.empty)
			chunkObservers.remove(cwp);
		else
			chunkObservers[cwp] = list;
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
