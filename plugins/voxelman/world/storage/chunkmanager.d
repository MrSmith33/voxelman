/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.chunkmanager;

import std.experimental.logger;
import std.typecons : Nullable;
import std.string : format;

import voxelman.block.utils;
import voxelman.core.config;
import voxelman.world.storage.chunk;
import voxelman.world.storage.coordinates : ChunkWorldPos, adjacentPositions;
import voxelman.world.storage.utils;
import voxelman.utils.hashset;
import voxelman.world.storage.chunkprovider;


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
		import core.memory : GC;

		if (blocks is null) return;
		if (blocks.length != CHUNK_SIZE_CUBE)
		{
			GC.free(blocks.ptr);
			return;
		}
		if (numItems == maxFreeItems) {
			GC.free(blocks.ptr);
			return;
		}
		items[numItems] = blocks;
		++numItems;
	}
}

struct ChunkSnapWithAdjacent
{
	union
	{
		ChunkWorldPos[7] positions;
		struct
		{
			ChunkWorldPos[6] adjacentPositions;
			ChunkWorldPos centralPosition;
		}
	}
	union
	{
		Nullable!ChunkLayerSnap[7] snapshots;
		struct
		{
			Nullable!ChunkLayerSnap[6] adjacentSnapshots;
			Nullable!ChunkLayerSnap centralSnapshot;
		}
	}
	bool allLoaded = true;
}

// Assumes that central chunk is loaded.
ChunkSnapWithAdjacent getSnapWithAdjacentAddUsers(ChunkManager cm, ChunkWorldPos cwp, size_t layer)
{
	ChunkSnapWithAdjacent result;

	result.centralSnapshot = cm.getChunkSnapshot(cwp, layer);
	result.centralPosition = cwp;

	result.adjacentPositions = adjacentPositions(cwp);

	result.allLoaded = !result.centralSnapshot.isNull();
	foreach(i, pos; result.adjacentPositions)
	{
		result.adjacentSnapshots[i] = cm.getChunkSnapshot(pos, layer);
		result.allLoaded = result.allLoaded && !result.adjacentSnapshots[i].isNull();
	}

	return result;
}

//version = DBG_OUT;
//version = DBG_COMPR;

final class ChunkChangeManager
{
	BlockChange[][ChunkWorldPos][] chunkChanges;
	ubyte numLayers;

	void setup(ubyte _numLayers) {
		numLayers = _numLayers;
		chunkChanges.length = numLayers;
	}

	import std.range : isInputRange, array;
	/// Call this whenewer changes to write buffer are done.
	void onBlockChanges(R)(ChunkWorldPos cwp, R blockChanges, size_t layer)
		if (isInputRange!(R))
	{
		chunkChanges[layer][cwp] = chunkChanges[layer].get(cwp, null) ~ blockChanges.array;
	}

	//void clearChunkData(ChunkWorldPos cwp) {
	//	assert(cwp !in chunkChanges[layer]);
	//}
}

final class ChunkManager {
	void delegate(ChunkWorldPos)[] onChunkAddedHandlers;
	void delegate(ChunkWorldPos)[] onChunkRemovedHandlers;
	void delegate(ChunkWorldPos) onChunkLoadedHandler;

	void delegate(ChunkWorldPos) loadChunkHandler;
	ChunkSaver delegate() startChunkSave; // Used on server only

	bool isLoadCancelingEnabled = false; /// Set to true on client to cancel load on unload
	bool isChunkSavingEnabled = true;

	private ChunkFreeList freeList;
	private ChunkLayerSnap[ChunkWorldPos][] snapshots;
	private ChunkLayerSnap[TimestampType][ChunkWorldPos][] oldSnapshots;
	private BlockId[][ChunkWorldPos][] writeBuffers;
	private ChunkState[ChunkWorldPos] chunkStates;
	private HashSet!ChunkWorldPos modifiedChunks;
	private size_t[ChunkWorldPos] numInternalChunkObservers;
	private size_t[ChunkWorldPos] numExternalChunkObservers;
	// total number of snapshot users of all 'snapshots'
	// used to change state from added_loaded to removed_loaded_used
	private size_t[ChunkWorldPos] totalSnapshotUsers;
	private ubyte numLayers;

	void setup(ubyte _numLayers) {
		numLayers = _numLayers;
		snapshots.length = numLayers;
		oldSnapshots.length = numLayers;
		writeBuffers.length = numLayers;
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
		clearModifiedChunks();
	}

	/// Used on client to clear modified chunks instead of saving them.
	void clearModifiedChunks()
	{
		modifiedChunks.clear();
	}

	HashSet!ChunkWorldPos getModifiedChunks()
	{
		return modifiedChunks;
	}

	bool isChunkLoaded(ChunkWorldPos cwp)
	{
		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		return state == ChunkState.added_loaded || state == ChunkState.added_loaded_saving;
	}

	private void saveChunk(ChunkWorldPos cwp)
	{
		assert(startChunkSave, "startChunkSave is null");
		ChunkSaver chunkSaver = startChunkSave();

		// code lower does work of addCurrentSnapshotUsers too
		ubyte numChunkLayers;
		foreach(ubyte layerId; 0..numLayers)
		{
			if (auto snap = cwp in snapshots[layerId])
			{
				++numChunkLayers;
				++snap.numUsers; // in case new snapshot replaces current one, we need to keep it while it is saved
				chunkSaver.pushLayer(ChunkLayerItem(*snap, layerId));
			}
		}
		totalSnapshotUsers[cwp] = totalSnapshotUsers.get(cwp, 0) + numChunkLayers;

		chunkSaver.endChunkSave(ChunkHeaderItem(cwp, numChunkLayers, 0));
	}

	/// Sets number of users of chunk at cwp.
	/// If total chunk users if greater than zero, then chunk is loaded,
	/// if equal to zero, chunk will be unloaded.
	void setExternalChunkObservers(ChunkWorldPos cwp, size_t numExternalObservers) {
		numExternalChunkObservers[cwp] = numExternalObservers;
		if (numExternalObservers == 0)
			numExternalChunkObservers.remove(cwp);
		setChunkTotalObservers(cwp, numInternalChunkObservers.get(cwp, 0) + numExternalObservers);
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

	/// Returns timestamp of current chunk snapshot.
	/// Store this timestamp to use in removeSnapshotUser
	TimestampType addCurrentSnapshotUser(ChunkWorldPos cwp, size_t layer) {
		auto snap = cwp in snapshots[layer];
		assert(snap, "Cannot add chunk user. No such snapshot.");

		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		assert(state == ChunkState.added_loaded || state == ChunkState.added_loaded_saving,
			format("To add user chunk must be both added and loaded, not %s", state));

		totalSnapshotUsers[cwp] = totalSnapshotUsers.get(cwp, 0) + 1;

		++snap.numUsers;
		return snap.timestamp;
	}

	void addCurrentSnapshotUsers(ChunkWorldPos cwp) {
		foreach(i; 0..numLayers) {
			addCurrentSnapshotUser(cwp, i);
		}
	}

	/// Generic removal of snapshot user. Removes chunk if numUsers == 0.
	/// Use this to remove added snapshot user. Use timestamp returned from addCurrentSnapshotUser.
	void removeSnapshotUser(ChunkWorldPos cwp, TimestampType timestamp, size_t layer) {
		auto snap = cwp in snapshots[layer];
		if (snap && snap.timestamp == timestamp) {
			auto totalUsersLeft = removeCurrentSnapshotUser(cwp, layer);
			if (totalUsersLeft == 0) {
				auto state = chunkStates.get(cwp, ChunkState.non_loaded);
				if (state == ChunkState.removed_loaded_used) {
					chunkStates[cwp] = ChunkState.non_loaded;
					clearChunkData(cwp);
				}
			}
		} else {
			removeOldSnapshotUser(cwp, timestamp, layer);
		}
	}

	/// Internal. Called by code which loads chunks from storage.
	/// LoadedChunk is a type that has following memeber:
	///   ChunkHeaderItem getHeader()
	///   ChunkLayerItem getLayer()
	void onSnapshotLoaded(LoadedChunk)(LoadedChunk chunk, bool isSaved) {
		ChunkHeaderItem header = chunk.getHeader();

		version(DBG_OUT)infof("res loaded %s", header.cwp);

		foreach(_; 0..header.numLayers)
		{
			ChunkLayerItem layer = chunk.getLayer();
			snapshots[layer.layerId][header.cwp] = ChunkLayerSnap(layer);
			version(DBG_COMPR)if (layer.type == StorageType.compressedArray)
				infof("CM Loaded %s %s %s\n(%(%02x%))", header.cwp, layer.dataPtr, layer.dataLength, layer.getArray!ubyte);
		}

		auto cwp = header.cwp;
		auto state = chunkStates.get(cwp, ChunkState.non_loaded);

		with(ChunkState) final switch(state)
		{
			case non_loaded:
				if (isLoadCancelingEnabled) {
					clearChunkData(cwp);
				} else {
					assert(false, "On loaded should not occur for already loaded chunk");
				}
				break;
			case added_loaded:
				assert(false, "On loaded should not occur for already loaded chunk");
			case removed_loading:
				if (isSaved || !isChunkSavingEnabled) {
					chunkStates[cwp] = non_loaded;
					clearChunkData(cwp);
				} else {
					assert(!isLoadCancelingEnabled, "Should happen only when isLoadCancelingEnabled is false");
					chunkStates[cwp] = added_loaded;
					saveChunk(cwp);
					chunkStates[cwp] = removed_loaded_saving;
				}
				break;
			case added_loading:
				chunkStates[cwp] = added_loaded;
				if (!isSaved) modifiedChunks.put(cwp);
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
	/// SavedChunk is a type that has following memeber:
	///   ChunkHeaderItem getHeader()
	///   ChunkLayerTimestampItem getLayerTimestamp()
	void onSnapshotSaved(SavedChunk)(SavedChunk chunk) {
		ChunkHeaderItem header = chunk.getHeader();
		version(DBG_OUT)infof("res saved %s", header.cwp);

		foreach(i; 0..header.numLayers)
		{
			ChunkLayerTimestampItem layer = chunk.getLayerTimestamp();
			removeSnapshotUser(header.cwp, layer.timestamp, layer.layerId);
		}

		// TODO remove code below once *_saving states are removed
		auto state = chunkStates.get(header.cwp, ChunkState.non_loaded);
		with(ChunkState) final switch(state)
		{
			case non_loaded:
				assert(false, "On saved should not occur for not added chunks");
			case added_loaded:
				assert(false, "On saved should not occur for not saving chunks");
			case removed_loading:
				assert(false, "On saved should not occur for not loaded chunks");
			case added_loading:
				assert(false, "On saved should not occur for not loaded chunks");
			case removed_loaded_saving:
				auto totalUsersLeft = totalSnapshotUsers.get(header.cwp, 0);
				if (totalUsersLeft == 0) {
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
				break;
		}
		mixin(traceStateStr);
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
		if (onChunkLoadedHandler) onChunkLoadedHandler(cwp);
	}

	// Puts chunk in added state requesting load if needed.
	// Notifies on add. Notifies on load if loaded.
	private void loadChunk(ChunkWorldPos cwp) {
		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		with(ChunkState) final switch(state) {
			case non_loaded:
				chunkStates[cwp] = added_loading;
				loadChunkHandler(cwp);
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
				if(cwp in modifiedChunks && isChunkSavingEnabled) {
					chunkStates[cwp] = removed_loaded_saving;
					saveChunk(cwp);
					modifiedChunks.remove(cwp);
				} else { // state 0
					auto totalUsersLeft = totalSnapshotUsers.get(cwp, 0);
					if (totalUsersLeft == 0) {
						chunkStates[cwp] = non_loaded;
						modifiedChunks.remove(cwp);
						clearChunkData(cwp);
					} else {
						chunkStates[cwp] = removed_loaded_used;
					}
				}
				break;
			case removed_loading:
				assert(false, "Unload should not occur when chunk is already removed");
			case added_loading:
				notifyRemoved(cwp);
				if (isLoadCancelingEnabled)
				{
					chunkStates[cwp] = non_loaded;
					clearChunkData(cwp);
				}
				else
				{
					chunkStates[cwp] = removed_loading;
				}
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
			if (auto snap = cwp in snapshots[layer])
			{
				recycleSnapshotMemory(*snap);
				snapshots[layer].remove(cwp);
				assert(cwp !in writeBuffers[layer]);
			}
			assert(cwp !in totalSnapshotUsers);
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
		addInternalObserver(cwp); // prevent unload until commit
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
	private void addInternalObserver(ChunkWorldPos cwp) {
		numInternalChunkObservers[cwp] = numInternalChunkObservers.get(cwp, 0) + 1;
		auto totalObservers = numInternalChunkObservers[cwp] + numExternalChunkObservers.get(cwp, 0);
		setChunkTotalObservers(cwp, totalObservers);
	}

	// Used inside chunk manager to remove chunk users.
	private void removeInternalObserver(ChunkWorldPos cwp) {
		auto numObservers = numInternalChunkObservers.get(cwp, 0);
		assert(numObservers > 0, "numInternalChunkObservers is zero when removing internal user");
		--numObservers;
		if (numObservers == 0)
			numInternalChunkObservers.remove(cwp);
		else
			numInternalChunkObservers[cwp] = numObservers;
		auto totalObservers = numObservers + numExternalChunkObservers.get(cwp, 0);
		setChunkTotalObservers(cwp, totalObservers);
	}

	// Returns number of current snapshot users left.
	private size_t removeCurrentSnapshotUser(ChunkWorldPos cwp, size_t layer) {
		auto snap = cwp in snapshots[layer];
		assert(snap && snap.numUsers > 0, "cannot remove chunk user. Snapshot has 0 users");

		auto totalUsers = cwp in totalSnapshotUsers;
		assert(totalUsers && (*totalUsers) > 0, "cannot remove chunk user. Snapshot has 0 users");

		--snap.numUsers;
		--(*totalUsers);

		if ((*totalUsers) == 0) {
			totalSnapshotUsers.remove(cwp);
		}

		return (*totalUsers);
	}

	// Returns that snapshot with updated numUsers.
	// Snapshot is removed from oldSnapshots if numUsers == 0.
	private void removeOldSnapshotUser(ChunkWorldPos cwp, TimestampType timestamp, size_t layer) {
		ChunkLayerSnap[TimestampType]* chunkSnaps = cwp in oldSnapshots[layer];
		assert(chunkSnaps, "old snapshot should have waited for releasing user");
		ChunkLayerSnap* snapshot = timestamp in *chunkSnaps;
		assert(snapshot, "cannot release snapshot user. No such snapshot");
		assert(snapshot.numUsers > 0, "cannot remove chunk user. Snapshot has 0 users");
		--snapshot.numUsers;
		if (snapshot.numUsers == 0) {
			(*chunkSnaps).remove(timestamp);
			if ((*chunkSnaps).length == 0) { // all old snaps of one chunk released
				oldSnapshots[layer].remove(cwp);
			}
			recycleSnapshotMemory(*snapshot);
		}
	}

	// Commit for single chunk.
	private void commitChunkSnapshot(ChunkWorldPos cwp, BlockId[] blocks, TimestampType currentTime, size_t layer) {
		auto currentSnapshot = getChunkSnapshot(cwp, layer);
		assert(!currentSnapshot.isNull);

		if (currentSnapshot.numUsers == 0) {
			recycleSnapshotMemory(currentSnapshot);
		} else {
			// transfer users from current layer snapshot into old snapshot
			auto totalUsers = cwp in totalSnapshotUsers;
			assert(totalUsers && (*totalUsers) >= currentSnapshot.numUsers, "layer has not enough users");
			(*totalUsers) -= currentSnapshot.numUsers;
			if ((*totalUsers) == 0) {
				totalSnapshotUsers.remove(cwp);
			}

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
		removeInternalObserver(cwp); // remove user added in getWriteBuffer

		mixin(traceStateStr);
	}

	// Called when snapshot data can be recycled.
	private void recycleSnapshotMemory(ChunkLayerSnap snap) {
		if (snap.type == StorageType.fullArray) {
			freeList.deallocate(snap.getArray!BlockId());
		} else if (snap.type == StorageType.compressedArray) {
			import core.memory : GC;
			GC.free(snap.getArray!ubyte().ptr);
		}
	}
}
