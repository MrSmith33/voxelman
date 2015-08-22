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
import voxelman.utils.log;

private enum ChunkState {
	non_loaded,
	added_loaded,
	removed_loading,
	added_loading,
	removed_loaded_saving,
	removed_loaded_used,
	added_loaded_saving,
}

private enum traceStateStr = q{
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
	private size_t[ChunkWorldPos] numInternalChunkUsers;
	private size_t[ChunkWorldPos] numExternalChunkUsers;

	void postUpdate(Timestamp currentTime) {
		commitSnapshots(currentTime);
		sendChanges();
	}

	void save() {
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

	void setChunkExternalObservers(ChunkWorldPos cwp, size_t numExternalObservers) {
		numExternalChunkUsers[cwp] = numExternalObservers;
		if (numExternalObservers == 0)
			numExternalChunkUsers.remove(cwp);
		setChunkTotalObservers(cwp, numInternalChunkUsers.get(cwp, 0) + numExternalObservers);
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
			newData = createWriteBuffer(cwp);
		}
		return newData;
	}

	void onBlockChange(ChunkWorldPos cwp, BlockChange blockChange) {
		chunkChanges[cwp] = chunkChanges.get(cwp, null) ~ blockChange;
	}

	// returns timestamp of current chunk snapshot.
	Timestamp addCurrentSnapshotUser(ChunkWorldPos cwp) {
		auto snap = cwp in snapshots;
		assert(snap, "Cannot add chunk user. No such snapshot.");

		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		assert(state == ChunkState.added_loaded || state == ChunkState.added_loaded_saving,
			"To add user chunk must be both added and loaded");

		++snap.numUsers;
		return snap.timestamp;
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
				assert(cwp !in writeBuffers, "Chunk with write buffer should not be unloaded");
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

	// fully removes chunk
	private void clearChunkData(ChunkWorldPos cwp) {
		snapshots.remove(cwp);
		assert(cwp !in writeBuffers);
		assert(cwp !in chunkChanges);
		assert(cwp !in modifiedChunks);
		chunkStates.remove(cwp);
	}

	// Creates write buffer for writing changes in it.
	// Latest snapshot's data is copied in it.
	// On commit stage this is moved into new snapshot and.
	// Adds internal user that is removed on commit to prevent unloading with uncommitted changes.
	private BlockId[] createWriteBuffer(ChunkWorldPos cwp) {
		assert(writeBuffers.get(cwp, null) is null);
		infof("   SNAP #%s", cwp);
		auto old = getChunkSnapshot(cwp);
		if (old.isNull) {
			warning("WARN Write buffer created for chunk without snapshot");
			return null;
		}
		auto newData = freeList.allocate();
		newData[] = old.blocks;
		writeBuffers[cwp] = newData;

		addInternalUser(cwp);
		return newData;
	}

	private void setChunkTotalObservers(ChunkWorldPos cwp, size_t totalObservers) {
		if (totalObservers > 0) {
			loadChunk(cwp);
		} else {
			unloadChunk(cwp);
		}
	}

	private void addInternalUser(ChunkWorldPos cwp) {
		numInternalChunkUsers[cwp] = numInternalChunkUsers.get(cwp, 0) + 1;
		auto totalUsers = numInternalChunkUsers[cwp] + numExternalChunkUsers.get(cwp, 0);
		setChunkTotalObservers(cwp, totalUsers);
	}

	private void removeInternalUser(ChunkWorldPos cwp) {
		auto numUsers = numInternalChunkUsers.get(cwp, 0);
		assert(numUsers > 0, "numInternalChunkUsers is zero when removing internal user");
		--numUsers;
		if (numUsers == 0)
			numInternalChunkUsers.remove(cwp);
		else
			numInternalChunkUsers[cwp] = numUsers;
		auto totalUsers = numUsers + numExternalChunkUsers.get(cwp, 0);
		setChunkTotalObservers(cwp, totalUsers);
	}

	private void clearWriteBuffers() {
		writeBuffers = null;
	}

	private void clearChunkChanges() {
		chunkChanges = null;
	}

	// returns number of current snapshot users left.
	private uint removeCurrentSnapshotUser(ChunkWorldPos cwp) {
		auto snap = cwp in snapshots;
		assert(snap, "Cannot remove chunk user. No such snapshot.");
		assert(snap.numUsers > 0, "cannot remove chunk user. Snapshot has 0 users.");
		--snap.numUsers;
		return snap.numUsers;
	}

	// Returns that snapshot with updated numUsers.
	// Snapshot is removed from oldSnapshots if numUsers == 0.
	private ChunkDataSnapshot removeOldSnapshotUser(ChunkWorldPos cwp, Timestamp timestamp) {
		ChunkDataSnapshot[Timestamp]* chunkSnaps = cwp in oldSnapshots;
		assert(chunkSnaps, "old snapshot should have waited for releasing user");
		ChunkDataSnapshot* snapshot = timestamp in *chunkSnaps;
		assert(snapshot, "cannot release snapshot user. No such snapshot");
		assert(snapshot.numUsers > 0, "snapshot with 0 users was not released");
		--snapshot.numUsers;
		if (snapshot.numUsers == 0) {
			(*chunkSnaps).remove(timestamp);
			if ((*chunkSnaps).length == 0) { // all old snaps of one chunk released
				oldSnapshots.remove(cwp);
			}
		}
		return *snapshot;
	}

	// called at the end of tick
	private void commitSnapshots(Timestamp currentTime) {
		auto writeBuffersCopy = writeBuffers;
		clearWriteBuffers();
		foreach(snapshot; writeBuffersCopy.byKeyValue) {
			auto cwp = snapshot.key;
			auto blocks = snapshot.value;
			modifiedChunks.put(cwp);
			commitChunkSnapshot(cwp, blocks, currentTime);
		}
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
				// Write buffer will be never returned when no snapshot is loaded.
				assert(false, "Commit is not possible for removed chunk");
			case added_loading:
				// Write buffer will be never returned when no snapshot is loaded.
				assert(false, "Commit is not possible for non-loaded chunk");
			case removed_loaded_saving:
				// This is guarded by internal user count.
				assert(false, "Commit is not possible for removed chunk");
			case removed_loaded_used:
				// This is guarded by internal user count.
				assert(false, "Commit is not possible for removed chunk");
			case added_loaded_saving:
				// This is now old snapshot with saving state. New one is not used by IO.
				chunkStates[cwp] = added_loaded;
				break;
		}
		removeInternalUser(cwp);

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

version(unittest) {
	private struct Handlers {
		void setup(ChunkManager cm) {
			cm.onChunkAddedHandlers ~= &onChunkAddedHandler;
			cm.onChunkRemovedHandlers ~= &onChunkRemovedHandler;
			cm.onChunkLoadedHandlers ~= &onChunkLoadedHandler;
			cm.chunkChangesHandlers ~= &chunkChangesHandler;
			cm.loadChunkHandler = &loadChunkHandler;
			cm.saveChunkHandler = &saveChunkHandler;
		}
		void onChunkAddedHandler(ChunkWorldPos) {
			onChunkAddedHandlerCalled = true;
		}
		void onChunkRemovedHandler(ChunkWorldPos) {
			onChunkRemovedHandlerCalled = true;
		}
		void onChunkLoadedHandler(ChunkWorldPos, ChunkDataSnapshot) {
			onChunkLoadedHandlerCalled = true;
		}
		void chunkChangesHandler(ChunkWorldPos, BlockChange[]) {
			chunkChangesHandlerCalled = true;
		}
		void loadChunkHandler(ChunkWorldPos cwp, BlockId[] outBuffer) {
			loadChunkHandlerCalled = true;
		}
		void saveChunkHandler(ChunkWorldPos cwp, ChunkDataSnapshot snapshot) {
			saveChunkHandlerCalled = true;
		}
		void assertCalled(size_t flags) {
			assert(!(((flags & 0b0000_0001) > 0) ^ onChunkAddedHandlerCalled));
			assert(!(((flags & 0b0000_0010) > 0) ^ onChunkRemovedHandlerCalled));
			assert(!(((flags & 0b0000_0100) > 0) ^ onChunkLoadedHandlerCalled));
			assert(!(((flags & 0b0000_1000) > 0) ^ chunkChangesHandlerCalled));
			assert(!(((flags & 0b0001_0000) > 0) ^ loadChunkHandlerCalled));
			assert(!(((flags & 0b0010_0000) > 0) ^ saveChunkHandlerCalled));
		}

		bool onChunkAddedHandlerCalled;
		bool onChunkRemovedHandlerCalled;
		bool onChunkLoadedHandlerCalled;
		bool chunkChangesHandlerCalled;
		bool loadChunkHandlerCalled;
		bool saveChunkHandlerCalled;
	}

	private struct FSMTester {
		auto cwp = ChunkWorldPos(0);
		auto currentState(ref ChunkManager cm) {
			return cm.chunkStates.get(ChunkWorldPos(0), ChunkState.non_loaded);
		}
		void resetChunk(ref ChunkManager cm) {
			cm.snapshots.remove(cwp);
			cm.oldSnapshots.remove(cwp);
			cm.writeBuffers.remove(cwp);
			cm.chunkChanges.remove(cwp);
			cm.chunkStates.remove(cwp);
			cm.modifiedChunks.remove(cwp);
			cm.numInternalChunkUsers.remove(cwp);
			cm.numExternalChunkUsers.remove(cwp);
		}
		void gotoState(ref ChunkManager cm, ChunkState state) {
			resetChunk(cm);
			with(ChunkState) final switch(state) {
				case non_loaded:
					break;
				case added_loaded:
					cm.setChunkExternalObservers(cwp, 1);
					cm.onSnapshotLoaded(cwp, ChunkDataSnapshot(new BlockId[16]));
					break;
				case removed_loading:
					cm.setChunkExternalObservers(cwp, 1);
					cm.setChunkExternalObservers(cwp, 0);
					break;
				case added_loading:
					cm.setChunkExternalObservers(cwp, 1);
					break;
				case removed_loaded_saving:
					gotoState(cm, ChunkState.added_loaded_saving);
					cm.setChunkExternalObservers(cwp, 0);
					break;
				case removed_loaded_used:
					gotoState(cm, ChunkState.added_loaded);
					cm.getWriteBuffer(cwp);
					cm.postUpdate(1);
					cm.addCurrentSnapshotUser(cwp);
					cm.save();
					cm.setChunkExternalObservers(cwp, 0);
					cm.onSnapshotSaved(cwp, ChunkDataSnapshot(new BlockId[16], Timestamp(1)));
					break;
				case added_loaded_saving:
					gotoState(cm, ChunkState.added_loaded);
					cm.getWriteBuffer(cwp);
					cm.postUpdate(1);
					cm.save();
					break;
			}
			import std.string : format;
			assert(currentState(cm) == state,
				format("Failed to set state %s, got %s", state, currentState(cm)));
		}
	}
}


unittest {
	setupLogger("snapmantest.log");

	Handlers h;
	ChunkManager cm;
	FSMTester fsmTester;
	ChunkWorldPos cwp = ChunkWorldPos(0);

	void assertState(ChunkState state) {
		import std.string : format;
		auto actualState = cm.chunkStates.get(ChunkWorldPos(0), ChunkState.non_loaded);
		assert(actualState == state,
			format("Got state '%s', while needed '%s'", actualState, state));
	}

	void resetHandlersState() {
		h = Handlers.init;
	}
	void resetChunkManager() {
		cm = new ChunkManager;
		h.setup(cm);
	}
	void reset() {
		resetHandlersState();
		resetChunkManager();
	}

	void setupState(ChunkState state) {
		fsmTester.gotoState(cm, state);
		resetHandlersState();
	}

	reset();

	//--------------------------------------------------------------------------
	// non_loaded -> added_loading
	cm.setChunkExternalObservers(cwp, 1);
	assertState(ChunkState.added_loading);
	assert(cm.getChunkSnapshot(ChunkWorldPos(0)).isNull);
	h.assertCalled(0b0001_0001); //onChunkAddedHandlerCalled, loadChunkHandlerCalled


	//--------------------------------------------------------------------------
	setupState(ChunkState.added_loading);
	// added_loading -> removed_loading
	cm.setChunkExternalObservers(cwp, 0);
	assertState(ChunkState.removed_loading);
	assert( cm.getChunkSnapshot(ChunkWorldPos(0)).isNull);
	h.assertCalled(0b0000_0010); //onChunkRemovedHandlerCalled


	//--------------------------------------------------------------------------
	setupState(ChunkState.removed_loading);
	// removed_loading -> added_loading
	cm.setChunkExternalObservers(cwp, 1);
	assertState(ChunkState.added_loading);
	assert( cm.getChunkSnapshot(ChunkWorldPos(0)).isNull);
	h.assertCalled(0b0000_0001); //onChunkAddedHandlerCalled


	//--------------------------------------------------------------------------
	setupState(ChunkState.removed_loading);
	// removed_loading -> non_loaded
	cm.onSnapshotLoaded(ChunkWorldPos(0), ChunkDataSnapshot(new BlockId[16]));
	assertState(ChunkState.non_loaded);
	assert( cm.getChunkSnapshot(ChunkWorldPos(0)).isNull); // null
	h.assertCalled(0b0000_0000);

	//--------------------------------------------------------------------------
	setupState(ChunkState.added_loading);
	// added_loading -> added_loaded
	cm.onSnapshotLoaded(ChunkWorldPos(0), ChunkDataSnapshot(new BlockId[16]));
	assertState(ChunkState.added_loaded);
	assert(!cm.getChunkSnapshot(ChunkWorldPos(0)).isNull); // !null
	h.assertCalled(0b0000_0100); //onChunkLoadedHandlerCalled

	//--------------------------------------------------------------------------
	setupState(ChunkState.added_loaded);
	// added_loaded -> non_loaded
	cm.setChunkExternalObservers(cwp, 0);
	assertState(ChunkState.non_loaded);
	h.assertCalled(0b0000_0010); //onChunkRemovedHandlerCalled

	//--------------------------------------------------------------------------
	setupState(ChunkState.added_loaded);
	// added_loaded -> removed_loaded_saving
	cm.getWriteBuffer(cwp);
	cm.postUpdate(Timestamp(1));
	cm.setChunkExternalObservers(cwp, 0);
	assertState(ChunkState.removed_loaded_saving);
	h.assertCalled(0b0010_0010); //onChunkRemovedHandlerCalled, loadChunkHandlerCalled


	//--------------------------------------------------------------------------
	setupState(ChunkState.added_loaded);
	// added_loaded -> added_loaded_saving
	cm.getWriteBuffer(cwp);
	cm.postUpdate(Timestamp(1));
	cm.save();
	assertState(ChunkState.added_loaded_saving);
	h.assertCalled(0b0010_0000); //loadChunkHandlerCalled


	//--------------------------------------------------------------------------
	setupState(ChunkState.added_loaded_saving);
	// added_loaded_saving -> added_loaded with commit
	cm.getWriteBuffer(cwp);
	cm.postUpdate(Timestamp(2));
	assertState(ChunkState.added_loaded);
	h.assertCalled(0b0000_0000);


	//--------------------------------------------------------------------------
	setupState(ChunkState.added_loaded_saving);
	// added_loaded_saving -> added_loaded with on_saved
	cm.onSnapshotSaved(cwp, ChunkDataSnapshot(new BlockId[16], Timestamp(1)));
	assertState(ChunkState.added_loaded);
	h.assertCalled(0b0000_0000);


	//--------------------------------------------------------------------------
	setupState(ChunkState.added_loaded_saving);
	// added_loaded_saving -> removed_loaded_saving
	cm.setChunkExternalObservers(cwp, 0);
	assertState(ChunkState.removed_loaded_saving);
	h.assertCalled(0b0000_0010); //onChunkRemovedHandlerCalled


	//--------------------------------------------------------------------------
	setupState(ChunkState.removed_loaded_saving);
	// removed_loaded_saving -> non_loaded
	cm.onSnapshotSaved(cwp, ChunkDataSnapshot(new BlockId[16], Timestamp(1)));
	assertState(ChunkState.non_loaded);
	h.assertCalled(0b0000_0000);


	//--------------------------------------------------------------------------
	setupState(ChunkState.added_loaded_saving);
	// removed_loaded_saving -> removed_loaded_used
	cm.addCurrentSnapshotUser(cwp);
	cm.setChunkExternalObservers(cwp, 0);
	assertState(ChunkState.removed_loaded_saving);
	cm.onSnapshotSaved(cwp, ChunkDataSnapshot(new BlockId[16], Timestamp(1)));
	assertState(ChunkState.removed_loaded_used);
	h.assertCalled(0b0000_0010); //onChunkRemovedHandlerCalled


	//--------------------------------------------------------------------------
	setupState(ChunkState.removed_loaded_saving);
	// removed_loaded_saving -> added_loaded_saving
	cm.setChunkExternalObservers(cwp, 1);
	assertState(ChunkState.added_loaded_saving);
	h.assertCalled(0b0000_0101); //onChunkAddedHandlerCalled, onChunkLoadedHandlerCalled


	//--------------------------------------------------------------------------
	setupState(ChunkState.removed_loaded_used);
	// removed_loaded_used -> non_loaded
	cm.removeSnapshotUser(cwp, Timestamp(1));
	assertState(ChunkState.non_loaded);
	h.assertCalled(0b0000_0000);


	//--------------------------------------------------------------------------
	setupState(ChunkState.removed_loaded_used);
	// removed_loaded_used -> added_loaded
	cm.setChunkExternalObservers(cwp, 1);
	assertState(ChunkState.added_loaded);
	h.assertCalled(0b0000_0101); //onChunkAddedHandlerCalled, onChunkLoadedHandlerCalled
}
