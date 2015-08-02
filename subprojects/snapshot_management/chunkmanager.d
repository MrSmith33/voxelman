/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module chunkmanager;

import std.experimental.logger;
import std.typecons : Nullable;
import server;
import voxelman.storage.utils;

private enum ChunkState {
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
