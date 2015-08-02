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
import voxelman.utils.queue;
import voxelman.storage.utils;


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

final class SnapshotProvider {
	void delegate(ChunkWorldPos, ChunkDataSnapshot) onSnapshotLoadedHandler;
	void delegate(ChunkWorldPos, ChunkDataSnapshot) onSnapshotSavedHandler;

	private ChunkInMemoryStorage inMemoryStorage; // Simulates delay of IO

	this() {
		inMemoryStorage.onChunkLoadedHandlers ~= &onSnapshotLoaded;
		inMemoryStorage.onChunkSavedHandlers ~= &onSnapshotSaved;
	}

	void update() {
		inMemoryStorage.update();
	}

	void loadChunk(ChunkWorldPos cwp, BlockId[] outBuffer) {
		inMemoryStorage.loadChunk(cwp, outBuffer);
	}

	// called if chunk was loaded before and needs to be saved
	void saveChunk(ChunkWorldPos cwp, ChunkDataSnapshot snapshot) {
		inMemoryStorage.saveChunk(cwp, snapshot);
	}

	private void onSnapshotLoaded(ChunkWorldPos cwp, ChunkDataSnapshot snapshot) {
		onSnapshotLoadedHandler(cwp, snapshot);
	}

	private void onSnapshotSaved(ChunkWorldPos cwp, ChunkDataSnapshot snapshot) {
		onSnapshotSavedHandler(cwp, snapshot);
	}
}

enum ChunkState {
	non_loaded,
	added_loaded,
	removed_loading,
	added_loading,
	removed_loaded_saving,
	removed_loaded_used,
	added_loaded_saving,
}

enum traceStateStr = q{
	infof("state #%s %s => %s", cwp, state,
		chunkStates.get(cwp, ChunkState.non_loaded));
};

final class ChunkManager {
	void delegate(ChunkWorldPos)[] onChunkAddedHandlers;
	void delegate(ChunkWorldPos)[] onChunkRemovedHandlers;
	void delegate(ChunkWorldPos, ChunkDataSnapshot)[] onChunkLoadedHandlers;
	void delegate(ChunkWorldPos, BlockChange[])[] chunkChangesHandlers;
	void delegate(ChunkWorldPos cwp, BlockId[] outBuffer) loadChunkHandler;
	void delegate(ChunkWorldPos cwp, ChunkDataSnapshot snapshot) saveChunkHandler;

	private ChunkFreeList freeList;
	private ChunkDataSnapshot[ChunkWorldPos] snapshots;
	private ChunkDataSnapshot[Timestamp][ChunkWorldPos] oldSnapshots;
	private BlockId[][ChunkWorldPos] writeBuffers;
	private BlockChange[][ChunkWorldPos] chunkChanges;
	private ChunkState[ChunkWorldPos] chunkStates;
	private HashSet!ChunkWorldPos modifiedChunks;

	void postUpdate(Timestamp currentTime) {
		commitSnapshots(currentTime);
		sendChanges();
	}

	void save(Timestamp currentTime) {
		foreach(cwp; modifiedChunks.items) {
			auto state = chunkStates.get(cwp, ChunkState.non_loaded);
			with(ChunkState) final switch(state) {
				case non_loaded:
					assert(false, "Save should not occur for not added chunks");
				case added_loaded:
					chunkStates[cwp] = added_loaded_saving;
					auto snap = cwp in snapshots;
					++snap.numUsers;
					saveChunkHandler(cwp, *snap);
					break;
				case removed_loading:
					assert(false, "Save should not occur for not loaded chunks");
				case added_loading:
					assert(false, "Save should not occur for not loaded chunks");
				case removed_loaded_saving:
					assert(false, "Save should not occur for not added chunks");
				case removed_loaded_used:
					assert(false, "Save should not occur for not added chunks");
				case added_loaded_saving:
					assert(false, "Save should not occur for not for saving chunk");
			}
			mixin(traceStateStr);
		}
		modifiedChunks.clear();
	}

	// returned value isNull if chunk is not loaded/added
	Nullable!ChunkDataSnapshot getChunkSnapshot(ChunkWorldPos cwp) {
		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		if (state == ChunkState.added_loaded || state == ChunkState.added_loaded_saving)
			return Nullable!ChunkDataSnapshot(snapshots[cwp]);
		else {
			return Nullable!ChunkDataSnapshot.init;
		}
	}

	// copies old snapshot data and returns it
	BlockId[] getWriteBuffer(ChunkWorldPos cwp) {
		auto newData = writeBuffers.get(cwp, null);
		if (newData is null) {
			infof("   SNAP #%s", cwp);
			auto old = getChunkSnapshot(cwp);
			if (old.isNull)
				return null;
			newData = freeList.allocate();
			newData[] = old.blocks;
			writeBuffers[cwp] = newData;
		}
		return newData;
	}

	void onBlockChange(ChunkWorldPos cwp, BlockChange blockChange) {
		chunkChanges[cwp] = chunkChanges.get(cwp, null) ~ blockChange;
	}

	void changeChunkNumObservers(ChunkWorldPos cwp, size_t numObservers) {
		if (numObservers > 0) {
			loadChunk(cwp);
		} else {
			unloadChunk(cwp);
		}
	}

	// returns timestamp of current chunk snapshot.
	Timestamp addCurrentSnapshotUser(ChunkWorldPos cwp) {
		auto snapshotPtr = cwp in snapshots;
		assert(snapshotPtr, "Cannot add chunk user. No such snapshot.");

		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		assert(state == ChunkState.added_loaded || state == ChunkState.added_loaded_saving,
			"To add user chunk must be both added and loaded");

		ChunkDataSnapshot snapshot = *snapshotPtr;
		++snapshot.numUsers;
		return snapshot.timestamp;
	}

	// Generic removal of snapshot user. Removes chunk if numUsers == 0.
	// Use this to remove added snapshot user. Use timestamp returned from addCurrentSnapshotUser.
	void removeSnapshotUser(ChunkWorldPos cwp, Timestamp timestamp) {
		auto snap = cwp in snapshots;
		if (snap && snap.timestamp == timestamp) {
			auto numUsersLeft = removeCurrentSnapshotUser(cwp);
			if (numUsersLeft == 0) {
				auto state = chunkStates.get(cwp, ChunkState.non_loaded);
				if (state == ChunkState.removed_loaded_used) {
					chunkStates[cwp] = ChunkState.non_loaded;
					clearChunkData(cwp);
				}
			}
		} else {
			auto snapshot = removeOldSnapshotUser(cwp, timestamp);
			if (snapshot.numUsers == 0)
				destroySnapshot(snapshot);
		}
	}

	//	PPPPPP  RRRRRR  IIIII VV     VV   AAA   TTTTTTT EEEEEEE
	//	PP   PP RR   RR  III  VV     VV  AAAAA    TTT   EE
	//	PPPPPP  RRRRRR   III   VV   VV  AA   AA   TTT   EEEEE
	//	PP      RR  RR   III    VV VV   AAAAAAA   TTT   EE
	//	PP      RR   RR IIIII    VVV    AA   AA   TTT   EEEEEEE
	//

	private void loadChunk(ChunkWorldPos cwp) {
		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		with(ChunkState) final switch(state) {
			case non_loaded:
				chunkStates[cwp] = added_loading;
				loadChunkHandler(cwp, freeList.allocate());
				addChunk(cwp);
				break;
			case added_loaded:
				break; // ignore
			case removed_loading:
				chunkStates[cwp] = added_loading;
				addChunk(cwp);
				break;
			case added_loading:
				break; // ignore
			case removed_loaded_saving:
				chunkStates[cwp] = added_loaded_saving;
				addChunk(cwp);
				notifyLoaded(cwp);
				break;
			case removed_loaded_used:
				chunkStates[cwp] = added_loaded;
				addChunk(cwp);
				notifyLoaded(cwp);
				break;
			case added_loaded_saving:
				break; // ignore
		}
		mixin(traceStateStr);
	}

	private void addChunk(ChunkWorldPos cwp) {
		foreach(handler; onChunkAddedHandlers)
			handler(cwp);
	}

	private void removeChunk(ChunkWorldPos cwp) {
		foreach(handler; onChunkRemovedHandlers)
			handler(cwp);
	}

	private void notifyLoaded(ChunkWorldPos cwp) {
		auto snap = getChunkSnapshot(cwp);
		assert(!snap.isNull);
		foreach(handler; onChunkLoadedHandlers)
			handler(cwp, snap.get);
	}

	private void unloadChunk(ChunkWorldPos cwp) {
		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		with(ChunkState) final switch(state) {
			case non_loaded:
				assert(false, "Unload should not occur when chunk was not yet loaded");
			case added_loaded:
				removeChunk(cwp);
				auto snap = cwp in snapshots;
				if(cwp in modifiedChunks) {
					chunkStates[cwp] = removed_loaded_saving;
					saveChunkHandler(cwp, *snap);
					++snap.numUsers;
					modifiedChunks.remove(cwp);
				} else { // state 0
					chunkStates[cwp] = non_loaded;
					clearChunkData(cwp);
				}
				break;
			case removed_loading:
				assert(false, "Unload should not occur when chunk is already removed");
			case added_loading:
				removeChunk(cwp);
				chunkStates[cwp] = removed_loading;
				break;
			case removed_loaded_saving:
				assert(false, "Unload should not occur when chunk is already removed");
			case removed_loaded_used:
				assert(false, "Unload should not occur when chunk is already removed");
			case added_loaded_saving:
				removeChunk(cwp);
				chunkStates[cwp] = removed_loaded_saving;
				break;
		}
		mixin(traceStateStr);
	}

	// fully remove chunk
	private void clearChunkData(ChunkWorldPos cwp) {
		snapshots.remove(cwp);
		assert(cwp !in writeBuffers);
		assert(cwp !in chunkChanges);
		assert(cwp !in modifiedChunks);
		chunkStates.remove(cwp);
	}

	private void clearWriteBuffers() {
		writeBuffers = null;
	}

	private void clearChunkChanges() {
		chunkChanges = null;
	}

	void onSnapshotLoaded(ChunkWorldPos cwp, ChunkDataSnapshot snap) {
		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		with(ChunkState) final switch(state) {
			case non_loaded:
				assert(false);
			case added_loaded:
				assert(false, "On loaded should not occur for already loaded chunk");
			case removed_loading:
				chunkStates[cwp] = non_loaded;
				clearChunkData(cwp);
				break;
			case added_loading:
				chunkStates[cwp] = added_loaded;
				snapshots[cwp] = ChunkDataSnapshot(snap.blocks, snap.timestamp);
				notifyLoaded(cwp);
				break;
			case removed_loaded_saving:
				assert(false, "On loaded should not occur for already loaded chunk");
			case removed_loaded_used:
				assert(false, "On loaded should not occur for already loaded chunk");
			case added_loaded_saving:
				assert(false, "On loaded should not occur for already loaded chunk");
		}
		mixin(traceStateStr);
	}

	void onSnapshotSaved(ChunkWorldPos cwp, ChunkDataSnapshot savedSnap) {
		auto snap = cwp in snapshots;
		if (snap && snap.timestamp == savedSnap.timestamp) {
			auto state = chunkStates.get(cwp, ChunkState.non_loaded);
			with(ChunkState) final switch(state) {
				case non_loaded:
					assert(false, "On saved should not occur for not added chunks");
				case added_loaded:
					assert(false, "On saved should not occur for not saving chunks");
				case removed_loading:
					assert(false, "On saved should not occur for not loaded chunks");
				case added_loading:
					assert(false, "On saved should not occur for not loaded chunks");
				case removed_loaded_saving:
					auto numUsersLeft = removeCurrentSnapshotUser(cwp);
					if (numUsersLeft == 0) {
						chunkStates[cwp] = non_loaded;
						clearChunkData(cwp);
					} else {
						chunkStates[cwp] = removed_loaded_used;
					}
					break;
				case removed_loaded_used:
					assert(false, "On saved should not occur for not saving chunks");
				case added_loaded_saving:
					chunkStates[cwp] = added_loaded;
					removeCurrentSnapshotUser(cwp);
					break;
			}
			mixin(traceStateStr);
		} else { // old snapshot saved
			auto snapshot = removeOldSnapshotUser(cwp, savedSnap.timestamp);
			if (snapshot.numUsers == 0)
				destroySnapshot(snapshot);
		}
	}

	// returns number of current snapshot users left.
	private uint removeCurrentSnapshotUser(ChunkWorldPos cwp) {
		auto snapshotPtr = cwp in snapshots;
		assert(snapshotPtr, "Cannot remove chunk user. No such snapshot.");
		ChunkDataSnapshot snapshot = *snapshotPtr;
		assert(snapshot.numUsers > 0, "cannot remove chunk user. Snapshot has 0 users.");
		--snapshot.numUsers;
		return snapshot.numUsers;
	}

	// Returns that snapshot with updated numUsers.
	// Snapshot is removed from oldSnapshots if numUsers == 0.
	private ChunkDataSnapshot removeOldSnapshotUser(ChunkWorldPos cwp, Timestamp timestamp) {
		ChunkDataSnapshot[Timestamp]* chunkSnaps = cwp in oldSnapshots;
		assert(chunkSnaps, "old snapshot should have waited for releasing user");
		ChunkDataSnapshot* snapshotPtr = timestamp in *chunkSnaps;
		assert(snapshotPtr, "cannot release snapshot user. No such snapshot");
		ChunkDataSnapshot snapshot = *snapshotPtr;
		assert(snapshot.numUsers > 0, "snapshot with 0 users was not released");
		--snapshot.numUsers;
		auto numUsersLeft = snapshot.numUsers;
		if (snapshot.numUsers == 0) {
			(*chunkSnaps).remove(timestamp);
			if ((*chunkSnaps).length == 0) { // all old snaps of one chunk released
				oldSnapshots.remove(cwp);
			}
		} else { // wait for other users
			(*chunkSnaps)[timestamp] = snapshot;
		}
		return snapshot;
	}

	// called at the end of tick
	private void commitSnapshots(Timestamp currentTime) {
		foreach(snapshot; writeBuffers.byKeyValue) {
			auto cwp = snapshot.key;
			auto blocks = snapshot.value;
			commitChunkSnapshot(cwp, blocks, currentTime);
			modifiedChunks.put(cwp);
		}
		clearWriteBuffers();
	}

	private void commitChunkSnapshot(ChunkWorldPos cwp, BlockId[] blocks, Timestamp currentTime) {
		auto currentSnapshot = getChunkSnapshot(cwp);
		assert(!currentSnapshot.isNull);
		if (currentSnapshot.numUsers == 0)
			destroySnapshot(currentSnapshot);
		else {
			ChunkDataSnapshot[Timestamp] chunkSnaps = oldSnapshots.get(cwp, null);
			assert(currentTime !in chunkSnaps);
			chunkSnaps[currentTime] = currentSnapshot.get;
		}
		infof("Old snapshot[%s]: time %s", cwp, currentTime);
		snapshots[cwp] = ChunkDataSnapshot(blocks, currentTime);

		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		with(ChunkState) final switch(state) {
			case non_loaded:
				assert(false, "Commit is not possible for non-loaded chunk");
			case added_loaded:
				break; // ignore
			case removed_loading:
				assert(false, "Commit is not possible for removed chunk");
			case added_loading:
				goto case non_loaded;
			case removed_loaded_saving:
				goto case removed_loading;
			case removed_loaded_used:
				goto case removed_loading;
			case added_loaded_saving:
				chunkStates[cwp] = added_loaded;
				break;
		}
		mixin(traceStateStr);
	}

	// Send changes to clients
	private void sendChanges() {
		foreach(changes; chunkChanges.byKeyValue) {
			foreach(handler; chunkChangesHandlers)
				handler(changes.key, changes.value);
		}
		clearChunkChanges();
	}

	private void destroySnapshot(ChunkDataSnapshot snap) {
		freeList.deallocate(snap.blocks);
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
		infof("  SETB #%s", chunkPos);
		blocks[blockPos.pos] = blockId;
		chunkManager.onBlockChange(chunkPos, BlockChange(blockPos, blockId));
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
		infof(" OBSV #%s by '%s'", cwp, clientId);
	}

	private void removeChunkObserver(ChunkWorldPos cwp, ClientId clientId) {
		auto list = chunkObservers.get(cwp, ChunkObservers.init);
		list.remove(clientId);
		changeChunkNumObservers(cwp, list.numObservers);
		if (list.empty)
			chunkObservers.remove(cwp);
		else
			chunkObservers[cwp] = list;
		infof(" UNOB #%s by '%s'", cwp, clientId);
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
