/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module chunkmanager;

import std.experimental.logger;
import std.typecons : Nullable;
import server : ChunkWorldPos, ChunkDataSnapshot, Timestamp, BlockId, ChunkFreeList, BlockChange, HashSet;

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
	//infof("state @%s %s => %s", cwp, state,
	//	chunkStates.get(cwp, ChunkState.non_loaded));
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


	/// Performs save of all modified chunks.
	/// Modified chunks
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

	/// Sets number of users of chunk at cwp.
	/// If total chunk users if greater than zero, then chunk is loaded,
	/// if equal to zero, chunk will be unloaded.
	void setExternalChunkUsers(ChunkWorldPos cwp, size_t numExternalUsers) {
		numExternalChunkUsers[cwp] = numExternalUsers;
		if (numExternalUsers == 0)
			numExternalChunkUsers.remove(cwp);
		setChunkTotalObservers(cwp, numInternalChunkUsers.get(cwp, 0) + numExternalUsers);
	}

	/// returned value isNull if chunk is not loaded/added
	Nullable!ChunkDataSnapshot getChunkSnapshot(ChunkWorldPos cwp) {
		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		if (state == ChunkState.added_loaded || state == ChunkState.added_loaded_saving)
			return Nullable!ChunkDataSnapshot(snapshots[cwp]);
		else {
			return Nullable!ChunkDataSnapshot.init;
		}
	}

	/// Returns writeable copy of current chunk snapshot.
	/// Any changes made to it must be reported trough onBlockChanges method.
	/// This buffer is valid until commit.
	/// After commit this buffer becomes next immutable snapshot.
	/// Returns null if chunk is not added and/or not loaded.
	BlockId[] getWriteBuffer(ChunkWorldPos cwp) {
		auto newData = writeBuffers.get(cwp, null);
		if (newData is null) {
			newData = createWriteBuffer(cwp);
		}
		return newData;
	}

	import std.range : isInputRange, array;
	/// Call this whenewer changes to write buffer are done.
	/// Those changes will be passed to chunkChangesHandlers to be handled when sendChanges is called.
	void onBlockChanges(R)(ChunkWorldPos cwp, R blockChanges)
		if (isInputRange!(R))
	{
		chunkChanges[cwp] = chunkChanges.get(cwp, null) ~ blockChanges.array;
	}

	/// Returns timestamp of current chunk snapshot.
	/// Store this timestamp to use in removeSnapshotUser
	Timestamp addCurrentSnapshotUser(ChunkWorldPos cwp) {
		auto snap = cwp in snapshots;
		assert(snap, "Cannot add chunk user. No such snapshot.");

		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		assert(state == ChunkState.added_loaded || state == ChunkState.added_loaded_saving,
			"To add user chunk must be both added and loaded");

		++snap.numUsers;
		return snap.timestamp;
	}

	/// Generic removal of snapshot user. Removes chunk if numUsers == 0.
	/// Use this to remove added snapshot user. Use timestamp returned from addCurrentSnapshotUser.
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
				recycleSnapshotMemory(snapshot);
		}
	}

	/// Internal. Called by code which loads chunks from storage.
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

	/// Internal. Called by code which saves chunks to storage.
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
				recycleSnapshotMemory(snapshot);
		}
	}

	/// called at the end of tick
	void commitSnapshots(Timestamp currentTime) {
		auto writeBuffersCopy = writeBuffers;
		clearWriteBuffers();
		foreach(snapshot; writeBuffersCopy.byKeyValue) {
			auto cwp = snapshot.key;
			auto blocks = snapshot.value;
			modifiedChunks.put(cwp);
			commitChunkSnapshot(cwp, blocks, currentTime);
		}
	}

	/// Send changes to clients
	void sendChanges() {
		foreach(changes; chunkChanges.byKeyValue) {
			foreach(handler; chunkChangesHandlers)
				handler(changes.key, changes.value);
		}
		clearChunkChanges();
	}

	//	PPPPPP  RRRRRR  IIIII VV     VV   AAA   TTTTTTT EEEEEEE
	//	PP   PP RR   RR  III  VV     VV  AAAAA    TTT   EE
	//	PPPPPP  RRRRRR   III   VV   VV  AA   AA   TTT   EEEEE
	//	PP      RR  RR   III    VV VV   AAAAAAA   TTT   EE
	//	PP      RR   RR IIIII    VVV    AA   AA   TTT   EEEEEEE
	//

	private void notifyAdded(ChunkWorldPos cwp) {
		foreach(handler; onChunkAddedHandlers)
			handler(cwp);
	}

	private void notifyRemoved(ChunkWorldPos cwp) {
		foreach(handler; onChunkRemovedHandlers)
			handler(cwp);
	}

	private void notifyLoaded(ChunkWorldPos cwp) {
		auto snap = getChunkSnapshot(cwp);
		assert(!snap.isNull);
		foreach(handler; onChunkLoadedHandlers)
			handler(cwp, snap);
	}

	// Puts chunk in added state requesting load if needed.
	// Notifies on add. Notifies on load if loaded.
	private void loadChunk(ChunkWorldPos cwp) {
		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		with(ChunkState) final switch(state) {
			case non_loaded:
				chunkStates[cwp] = added_loading;
				loadChunkHandler(cwp, freeList.allocate());
				notifyAdded(cwp);
				break;
			case added_loaded:
				break; // ignore
			case removed_loading:
				chunkStates[cwp] = added_loading;
				notifyAdded(cwp);
				break;
			case added_loading:
				break; // ignore
			case removed_loaded_saving:
				chunkStates[cwp] = added_loaded_saving;
				notifyAdded(cwp);
				notifyLoaded(cwp);
				break;
			case removed_loaded_used:
				chunkStates[cwp] = added_loaded;
				notifyAdded(cwp);
				notifyLoaded(cwp);
				break;
			case added_loaded_saving:
				break; // ignore
		}
		mixin(traceStateStr);
	}

	// Puts chunk in removed state requesting save if needed.
	// Notifies on remove.
	private void unloadChunk(ChunkWorldPos cwp) {
		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		with(ChunkState) final switch(state) {
			case non_loaded:
				assert(false, "Unload should not occur when chunk was not yet loaded");
			case added_loaded:
				assert(cwp !in writeBuffers, "Chunk with write buffer should not be unloaded");
				notifyRemoved(cwp);
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
				notifyRemoved(cwp);
				chunkStates[cwp] = removed_loading;
				break;
			case removed_loaded_saving:
				assert(false, "Unload should not occur when chunk is already removed");
			case removed_loaded_used:
				assert(false, "Unload should not occur when chunk is already removed");
			case added_loaded_saving:
				notifyRemoved(cwp);
				chunkStates[cwp] = removed_loaded_saving;
				break;
		}
		mixin(traceStateStr);
	}

	// Fully removes chunk
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
		auto old = getChunkSnapshot(cwp);
		if (old.isNull) {
			return null;
		}
		auto newData = freeList.allocate();
		newData[] = old.blocks;
		writeBuffers[cwp] = newData;
		addInternalUser(cwp); // prevent unload until commit
		return newData;
	}

	// Here comes sum of all internal and external chunk users which results in loading or unloading of specific chunk.
	private void setChunkTotalObservers(ChunkWorldPos cwp, size_t totalObservers) {
		if (totalObservers > 0) {
			loadChunk(cwp);
		} else {
			unloadChunk(cwp);
		}
	}

	// Used inside chunk manager to add chunk users, to prevent chunk unloading.
	private void addInternalUser(ChunkWorldPos cwp) {
		numInternalChunkUsers[cwp] = numInternalChunkUsers.get(cwp, 0) + 1;
		auto totalUsers = numInternalChunkUsers[cwp] + numExternalChunkUsers.get(cwp, 0);
		setChunkTotalObservers(cwp, totalUsers);
	}

	// Used inside chunk manager to remove chunk users.
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

	// Returns number of current snapshot users left.
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

	// Commit for single chunk.
	private void commitChunkSnapshot(ChunkWorldPos cwp, BlockId[] blocks, Timestamp currentTime) {
		auto currentSnapshot = getChunkSnapshot(cwp);
		assert(!currentSnapshot.isNull);
		if (currentSnapshot.numUsers == 0)
			recycleSnapshotMemory(currentSnapshot);
		else {
			ChunkDataSnapshot[Timestamp] chunkSnaps = oldSnapshots.get(cwp, null);
			assert(currentTime !in chunkSnaps);
			chunkSnaps[currentTime] = currentSnapshot.get;
		}
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
		removeInternalUser(cwp); // remove user added in getWriteBuffer

		mixin(traceStateStr);
	}

	// Called when snapshot data can be recycled.
	private void recycleSnapshotMemory(ChunkDataSnapshot snap) {
		freeList.deallocate(snap.blocks);
	}
}

//	TTTTTTT EEEEEEE  SSSSS  TTTTTTT  SSSSS
//	  TTT   EE      SS        TTT   SS
//	  TTT   EEEEE    SSSSS    TTT    SSSSS
//	  TTT   EE           SS   TTT        SS
//	  TTT   EEEEEEE  SSSSS    TTT    SSSSS
//

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
					cm.setExternalChunkUsers(cwp, 1);
					cm.onSnapshotLoaded(cwp, ChunkDataSnapshot(new BlockId[16]));
					break;
				case removed_loading:
					cm.setExternalChunkUsers(cwp, 1);
					cm.setExternalChunkUsers(cwp, 0);
					break;
				case added_loading:
					cm.setExternalChunkUsers(cwp, 1);
					break;
				case removed_loaded_saving:
					gotoState(cm, ChunkState.added_loaded_saving);
					cm.setExternalChunkUsers(cwp, 0);
					break;
				case removed_loaded_used:
					gotoState(cm, ChunkState.added_loaded);
					cm.getWriteBuffer(cwp);
					cm.commitSnapshots(1);
					cm.addCurrentSnapshotUser(cwp);
					cm.save();
					cm.setExternalChunkUsers(cwp, 0);
					cm.onSnapshotSaved(cwp, ChunkDataSnapshot(new BlockId[16], Timestamp(1)));
					break;
				case added_loaded_saving:
					gotoState(cm, ChunkState.added_loaded);
					cm.getWriteBuffer(cwp);
					cm.commitSnapshots(1);
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
	import voxelman.utils.log : setupLogger;
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
	cm.setExternalChunkUsers(cwp, 1);
	assertState(ChunkState.added_loading);
	assert(cm.getChunkSnapshot(ChunkWorldPos(0)).isNull);
	h.assertCalled(0b0001_0001); //onChunkAddedHandlerCalled, loadChunkHandlerCalled


	//--------------------------------------------------------------------------
	setupState(ChunkState.added_loading);
	// added_loading -> removed_loading
	cm.setExternalChunkUsers(cwp, 0);
	assertState(ChunkState.removed_loading);
	assert( cm.getChunkSnapshot(ChunkWorldPos(0)).isNull);
	h.assertCalled(0b0000_0010); //onChunkRemovedHandlerCalled


	//--------------------------------------------------------------------------
	setupState(ChunkState.removed_loading);
	// removed_loading -> added_loading
	cm.setExternalChunkUsers(cwp, 1);
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
	cm.setExternalChunkUsers(cwp, 0);
	assertState(ChunkState.non_loaded);
	h.assertCalled(0b0000_0010); //onChunkRemovedHandlerCalled

	//--------------------------------------------------------------------------
	setupState(ChunkState.added_loaded);
	// added_loaded -> removed_loaded_saving
	cm.getWriteBuffer(cwp);
	cm.commitSnapshots(Timestamp(1));
	cm.setExternalChunkUsers(cwp, 0);
	assertState(ChunkState.removed_loaded_saving);
	h.assertCalled(0b0010_0010); //onChunkRemovedHandlerCalled, loadChunkHandlerCalled


	//--------------------------------------------------------------------------
	setupState(ChunkState.added_loaded);
	// added_loaded -> added_loaded_saving
	cm.getWriteBuffer(cwp);
	cm.commitSnapshots(Timestamp(1));
	cm.save();
	assertState(ChunkState.added_loaded_saving);
	h.assertCalled(0b0010_0000); //loadChunkHandlerCalled


	//--------------------------------------------------------------------------
	setupState(ChunkState.added_loaded_saving);
	// added_loaded_saving -> added_loaded with commit
	cm.getWriteBuffer(cwp);
	cm.commitSnapshots(Timestamp(2));
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
	cm.setExternalChunkUsers(cwp, 0);
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
	cm.setExternalChunkUsers(cwp, 0);
	assertState(ChunkState.removed_loaded_saving);
	cm.onSnapshotSaved(cwp, ChunkDataSnapshot(new BlockId[16], Timestamp(1)));
	assertState(ChunkState.removed_loaded_used);
	h.assertCalled(0b0000_0010); //onChunkRemovedHandlerCalled


	//--------------------------------------------------------------------------
	setupState(ChunkState.removed_loaded_saving);
	// removed_loaded_saving -> added_loaded_saving
	cm.setExternalChunkUsers(cwp, 1);
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
	cm.setExternalChunkUsers(cwp, 1);
	assertState(ChunkState.added_loaded);
	h.assertCalled(0b0000_0101); //onChunkAddedHandlerCalled, onChunkLoadedHandlerCalled
}
