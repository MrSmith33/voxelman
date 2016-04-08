/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.storage.chunkmanager;

import std.experimental.logger;
import std.typecons : Nullable;

import voxelman.block.utils;
import voxelman.core.config;
import voxelman.storage.chunk;
import voxelman.storage.coordinates : ChunkWorldPos;
import voxelman.storage.utils;
import voxelman.utils.hashset;
import voxelman.storage.chunkprovider;


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

enum maxFreeItems = 200;
struct ChunkFreeList {
	BlockId[][maxFreeItems] items;
	size_t numItems;

	BlockId[] allocate() {
		import std.array : uninitializedArray;
		if (numItems > 0) {
			--numItems;
			BlockId[] item = items[numItems];
			items[numItems] = null;
			return item;
		} else {
			return uninitializedArray!(BlockId[])(CHUNK_SIZE_CUBE);
		}
	}

	void deallocate(BlockId[] blocks) {
		if (blocks is null) return;
		if (numItems == maxFreeItems) {
			delete(blocks);
			return;
		}
		items[numItems] = blocks;
		++numItems;
	}
}

enum FIRST_LAYER = 0;
//version = DBG_OUT;

final class ChunkManager {
	void delegate(ChunkWorldPos)[] onChunkAddedHandlers;
	void delegate(ChunkWorldPos)[] onChunkRemovedHandlers;
	void delegate(ChunkWorldPos) onChunkLoadedHandler;
	void delegate(BlockChange[][ChunkWorldPos])[] chunkChangesHandlers;
	ChunkProvider* chunkProvider;

	private ChunkFreeList freeList;
	private ChunkLayerSnap[ChunkWorldPos][] snapshots;
	private ChunkLayerSnap[TimestampType][ChunkWorldPos][] oldSnapshots;
	private BlockId[][ChunkWorldPos][] writeBuffers;
	private BlockChange[][ChunkWorldPos][] chunkChanges;
	private ChunkState[ChunkWorldPos] chunkStates;
	private HashSet!ChunkWorldPos modifiedChunks;
	private size_t[ChunkWorldPos] numInternalChunkUsers;
	private size_t[ChunkWorldPos] numExternalChunkUsers;
	private ubyte numLayers;

	void setup(ubyte _numLayers) {
		numLayers = _numLayers;
		snapshots.length = numLayers;
		oldSnapshots.length = numLayers;
		writeBuffers.length = numLayers;
		chunkChanges.length = numLayers;
	}

	/// Performs save of all modified chunks.
	/// Modified chunks are those that were committed.
	/// Perform save right after commit.
	void save() {
		foreach(cwp; modifiedChunks.items) {
			auto state = chunkStates.get(cwp, ChunkState.non_loaded);
			with(ChunkState) final switch(state) {
				case non_loaded:
					assert(false, "Save should not occur for not added chunks");
				case added_loaded:
					chunkStates[cwp] = added_loaded_saving;
					saveChunk(cwp);
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

	void saveChunk(ChunkWorldPos cwp)
	{
		chunkProvider.saveTaskQueue.startPush();
		size_t headerPos = chunkProvider.saveTaskQueue.skipItemDelayed!ChunkHeaderItem();
		ubyte numChunkLayers;
		foreach(ubyte layerId; 0..numLayers)
		{
			if (auto snap = cwp in snapshots[layerId])
			{
				++numChunkLayers;
				++snap.numUsers; // in case new snapshot replaces current one, we need to keep it while it is saved
				chunkProvider.saveTaskQueue.pushItem(ChunkLayerItem(*snap, layerId));
			}
		}
		chunkProvider.saveTaskQueue.setItem(ChunkHeaderItem(cwp, numChunkLayers, 0), headerPos);
		chunkProvider.saveTaskQueue.endPush();
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
	Nullable!ChunkLayerSnap getChunkSnapshot(ChunkWorldPos cwp, size_t layer) {
		assert(layer == 0);
		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		if (state == ChunkState.added_loaded || state == ChunkState.added_loaded_saving) {
			auto snap = cwp in snapshots[layer];
			if (snap) { // TODO no nulls allowed here
				assert(snap);
				auto res = Nullable!ChunkLayerSnap(*snap);
				return res;
			}
		}

		auto res = Nullable!ChunkLayerSnap.init;
		return res;
	}

	/// Returns writeable copy of current chunk snapshot.
	/// Any changes made to it must be reported trough onBlockChanges method.
	/// This buffer is valid until commit.
	/// After commit this buffer becomes next immutable snapshot.
	/// Returns null if chunk is not added and/or not loaded.
	BlockId[] getWriteBuffer(ChunkWorldPos cwp, size_t layer) {
		auto newData = writeBuffers[layer].get(cwp, null);
		if (newData is null) {
			newData = createWriteBuffer(cwp, layer);
		}
		return newData;
	}

	import std.range : isInputRange, array;
	/// Call this whenewer changes to write buffer are done.
	/// Those changes will be passed to chunkChangesHandlers to be handled when sendChanges is called.
	void onBlockChanges(R)(ChunkWorldPos cwp, R blockChanges, size_t layer)
		if (isInputRange!(R))
	{
		chunkChanges[layer][cwp] = chunkChanges[layer].get(cwp, null) ~ blockChanges.array;
	}

	/// Returns timestamp of current chunk snapshot.
	/// Store this timestamp to use in removeSnapshotUser
	TimestampType addCurrentSnapshotUser(ChunkWorldPos cwp, size_t layer) {
		auto snap = cwp in snapshots[layer];
		assert(snap, "Cannot add chunk user. No such snapshot.");

		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		assert(state == ChunkState.added_loaded || state == ChunkState.added_loaded_saving,
			format("To add user chunk must be both added and loaded, not %s", state));

		++snap.numUsers;
		return snap.timestamp;
	}

	void addCurrentSnapshotUsers(ChunkWorldPos cwp) {
		foreach(i; 0..numLayers)
			addCurrentSnapshotUser(cwp, i);
	}

	/// Generic removal of snapshot user. Removes chunk if numUsers == 0.
	/// Use this to remove added snapshot user. Use timestamp returned from addCurrentSnapshotUser.
	void removeSnapshotUser(ChunkWorldPos cwp, TimestampType timestamp, size_t layer) {
		auto snap = cwp in snapshots[layer];
		if (snap && snap.timestamp == timestamp) {
			auto numUsersLeft = removeCurrentSnapshotUser(cwp, layer);
			if (numUsersLeft == 0) {
				auto state = chunkStates.get(cwp, ChunkState.non_loaded);
				if (state == ChunkState.removed_loaded_used) {
					chunkStates[cwp] = ChunkState.non_loaded;
					clearChunkData(cwp);
				}
			}
		} else {
			auto snapshot = removeOldSnapshotUser(cwp, timestamp, layer);
			if (snapshot.numUsers == 0)
				recycleSnapshotMemory(snapshot);
		}
	}

	/// Internal. Called by code which loads chunks from storage.
	void onSnapshotLoaded(shared(MessageQueue)* queue, bool generated) {
		assert(queue.length >= 2);
		ChunkHeaderItem header = queue.popItem!ChunkHeaderItem();
		version(DBG_OUT)infof("res loaded %s", header.cwp);
		assert(queue.length >= ChunkLayerItem.sizeof/8 * header.numLayers);
		foreach(_; 0..header.numLayers) {
			ChunkLayerItem layer = queue.popItem!ChunkLayerItem();
			snapshots[layer.layerId][header.cwp] = ChunkLayerSnap(layer);
		}

		bool saved = !!header.metadata&1;
		auto cwp = header.cwp;
		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		with(ChunkState) final switch(state) {
			case non_loaded:
				assert(false, "On loaded should not occur for already loaded chunk");
			case added_loaded:
				assert(false, "On loaded should not occur for already loaded chunk");
			case removed_loading:
				if (generated) {
					chunkStates[cwp] = added_loaded;
					saveChunk(cwp);
					addCurrentSnapshotUsers(cwp);
					chunkStates[cwp] = removed_loaded_saving;
				} else {
					chunkStates[cwp] = non_loaded;
					clearChunkData(cwp);
				}
				break;
			case added_loading:
				chunkStates[cwp] = added_loaded;
				if (!saved) modifiedChunks.put(cwp);
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
	void onSnapshotSaved() {
		ChunkHeaderItem header = chunkProvider.saveResQueue.popItem!ChunkHeaderItem();
		version(DBG_OUT)infof("res saved %s", header.cwp);
		foreach(_; 0..header.numLayers) {
			auto layer = chunkProvider.saveResQueue.popItem!ChunkLayerTimestampItem();
			auto snap = header.cwp in snapshots[layer.layerId];
			if (snap && snap.timestamp == layer.timestamp) {
				auto state = chunkStates.get(header.cwp, ChunkState.non_loaded);
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
						auto numUsersLeft = removeCurrentSnapshotUser(header.cwp, layer.layerId);
						if (numUsersLeft == 0) {
							chunkStates[header.cwp] = non_loaded;
							clearChunkData(header.cwp);
						} else {
							chunkStates[header.cwp] = removed_loaded_used;
						}
						break;
					case removed_loaded_used:
						assert(false, "On saved should not occur for not saving chunks");
					case added_loaded_saving:
						chunkStates[header.cwp] = added_loaded;
						removeCurrentSnapshotUser(header.cwp, layer.layerId);
						break;
				}
				mixin(traceStateStr);
			} else { // old snapshot saved
				auto snapshot = removeOldSnapshotUser(header.cwp, layer.timestamp, layer.layerId);
				if (snapshot.numUsers == 0)
					recycleSnapshotMemory(snapshot);
			}
		}
	}

	/// called at the end of tick
	void commitSnapshots(TimestampType currentTime) {
		foreach(layer; 0..numLayers)
		{
			auto writeBuffersCopy = writeBuffers[layer];
			// Clear it here because commit can unload chunk.
			// And unload asserts that chunk is not in writeBuffers.
			writeBuffers[layer] = null;
			foreach(snapshot; writeBuffersCopy.byKeyValue) {
				auto cwp = snapshot.key;
				auto blockData = snapshot.value;
				modifiedChunks.put(cwp);
				commitChunkSnapshot(cwp, blockData, currentTime, layer);
			}
		}
	}

	/// Send changes to clients
	void sendChanges() {
		foreach(layer; 0..numLayers)
		{
			foreach(handler; chunkChangesHandlers)
					handler(chunkChanges[layer]);
			chunkChanges[layer] = null;
		}
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
		onChunkLoadedHandler(cwp);
	}

	// Puts chunk in added state requesting load if needed.
	// Notifies on add. Notifies on load if loaded.
	private void loadChunk(ChunkWorldPos cwp) {
		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		with(ChunkState) final switch(state) {
			case non_loaded:
				chunkStates[cwp] = added_loading;
				chunkProvider.loadTaskQueue.pushSingleItem!ulong(cwp.asUlong);
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
				//assert(cwp !in writeBuffers[FIRST_LAYER], "Chunk with write buffer should not be unloaded");
				notifyRemoved(cwp);
				//auto snap = cwp in snapshots[FIRST_LAYER];
				if(cwp in modifiedChunks) {
					chunkStates[cwp] = removed_loaded_saving;
					saveChunk(cwp);
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
		foreach(layer; 0..numLayers)
		{
			recycleSnapshotMemory(snapshots[layer][cwp]);
			snapshots[layer].remove(cwp);
			assert(cwp !in writeBuffers[layer]);
			assert(cwp !in chunkChanges[layer]);
		}
		assert(cwp !in modifiedChunks);
		chunkStates.remove(cwp);
	}

	// Creates write buffer for writing changes in it.
	// Latest snapshot's data is copied in it.
	// On commit stage this is moved into new snapshot and.
	// Adds internal user that is removed on commit to prevent unloading with uncommitted changes.
	private BlockId[] createWriteBuffer(ChunkWorldPos cwp, size_t layer) {
		assert(writeBuffers[layer].get(cwp, null) is null);
		auto old = getChunkSnapshot(cwp, layer);
		if (old.isNull) {
			return null;
		}
		auto buffer = freeList.allocate();
		old.copyToBuffer(buffer);
		writeBuffers[layer][cwp] = buffer;
		addInternalUser(cwp); // prevent unload until commit
		return buffer;
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

	// Returns number of current snapshot users left.
	private uint removeCurrentSnapshotUser(ChunkWorldPos cwp, size_t layer) {
		auto snap = cwp in snapshots[layer];
		assert(snap, "Cannot remove chunk user. No such snapshot.");
		assert(snap.numUsers > 0, "cannot remove chunk user. Snapshot has 0 users.");
		--snap.numUsers;
		return snap.numUsers;
	}

	// Returns that snapshot with updated numUsers.
	// Snapshot is removed from oldSnapshots if numUsers == 0.
	private ChunkLayerSnap removeOldSnapshotUser(ChunkWorldPos cwp, TimestampType timestamp, size_t layer) {
		ChunkLayerSnap[TimestampType]* chunkSnaps = cwp in oldSnapshots[layer];
		assert(chunkSnaps, "old snapshot should have waited for releasing user");
		ChunkLayerSnap* snapshot = timestamp in *chunkSnaps;
		assert(snapshot, "cannot release snapshot user. No such snapshot");
		assert(snapshot.numUsers > 0, "snapshot with 0 users was not released");
		--snapshot.numUsers;
		if (snapshot.numUsers == 0) {
			(*chunkSnaps).remove(timestamp);
			if ((*chunkSnaps).length == 0) { // all old snaps of one chunk released
				oldSnapshots[layer].remove(cwp);
			}
		}
		return *snapshot;
	}

	// Commit for single chunk.
	private void commitChunkSnapshot(ChunkWorldPos cwp, BlockId[] blocks, TimestampType currentTime, size_t layer) {
		auto currentSnapshot = getChunkSnapshot(cwp, layer);
		assert(!currentSnapshot.isNull);
		if (currentSnapshot.numUsers == 0)
			recycleSnapshotMemory(currentSnapshot);
		else {
			ChunkLayerSnap[TimestampType] chunkSnaps = oldSnapshots[layer].get(cwp, null);
			assert(currentTime !in chunkSnaps);
			chunkSnaps[currentTime] = currentSnapshot.get;
		}
		snapshots[layer][cwp] = ChunkLayerSnap(StorageType.fullArray, currentTime, blocks);

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
	private void recycleSnapshotMemory(ChunkLayerSnap snap) {
		if (snap.type != StorageType.uniform)
			freeList.deallocate(snap.getArray!BlockId());
	}
}
