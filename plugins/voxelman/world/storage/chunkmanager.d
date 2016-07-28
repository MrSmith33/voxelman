/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.chunkmanager;

import std.experimental.logger;
import std.typecons : Nullable;
import std.string : format;
public import std.typecons : Flag, Yes, No;

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
	removed_loaded_used
}

private enum traceStateStr = q{
	//infof("state @%s %s => %s", cwp, state,
	//	chunkStates.get(cwp, ChunkState.non_loaded));
};

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

ChunkSnapWithAdjacent getSnapWithAdjacent(ChunkManager cm, ChunkWorldPos cwp, ubyte layer)
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

//version = TRACE_SNAP_USERS;
//version = DBG_OUT;
//version = DBG_COMPR;

enum WriteBufferPolicy
{
	createUniform,
	copySnapshotArray,
}

final class ChunkManager {
	void delegate(ChunkWorldPos)[] onChunkAddedHandlers;
	void delegate(ChunkWorldPos)[] onChunkRemovedHandlers;
	void delegate(ChunkWorldPos) onChunkLoadedHandler;

	void delegate(ChunkWorldPos) loadChunkHandler;

	// Used on server only
	size_t delegate() startChunkSave;
	void delegate(ChunkLayerItem layer) pushLayer;
	void delegate(size_t headerPos, ChunkHeaderItem header) endChunkSave;

	bool isLoadCancelingEnabled = false; /// Set to true on client to cancel load on unload
	bool isChunkSavingEnabled = true;
	long totalLayerDataBytes; // debug

	private ChunkLayerSnap[ChunkWorldPos][] snapshots;
	private ChunkLayerSnap[TimestampType][ChunkWorldPos][] oldSnapshots;
	private WriteBuffer[ChunkWorldPos][] writeBuffers;
	private ChunkState[ChunkWorldPos] chunkStates;
	private HashSet!ChunkWorldPos modifiedChunks;
	private size_t[ChunkWorldPos] numInternalChunkObservers;
	private size_t[ChunkWorldPos] numExternalChunkObservers;
	// total number of snapshot users of all 'snapshots'
	// used to change state from added_loaded to removed_loaded_used
	private size_t[ChunkWorldPos] totalSnapshotUsers;
	ubyte numLayers;

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
			saveChunk(cwp);
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
		return state == ChunkState.added_loaded;
	}

	bool isChunkAdded(ChunkWorldPos cwp)
	{
		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		with(ChunkState) {
			return state == added_loaded || state == added_loading;
		}
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
	/// If uncompress is Yes then tries to convert snapshot to uncompressed.
	/// If has users, then compressed snapshot is returned.
	Nullable!ChunkLayerSnap getChunkSnapshot(ChunkWorldPos cwp, ubyte layer, Flag!"Uncompress" uncompress = Flag!"Uncompress".no) {
		if (isChunkLoaded(cwp))
		{
			auto snap = cwp in snapshots[layer];
			if (snap)
			{
				if (snap.type == StorageType.compressedArray && uncompress)
				{
					ubyte[] decompressedData = decompressLayerData((*snap).getArray!ubyte);
					if (snap.numUsers == 0) {
						recycleSnapshotMemory(*snap);
						snap.dataPtr = decompressedData.ptr;
						snap.dataLength = cast(LayerDataLenType)decompressedData.length;
						snap.type = StorageType.fullArray;
					}
					else
					{
						ChunkLayerSnap res = *snap;
						res.dataPtr = decompressedData.ptr;
						res.dataLength = cast(LayerDataLenType)decompressedData.length;
						res.type = StorageType.fullArray;
						return Nullable!ChunkLayerSnap(res);
					}
				}
				auto res = Nullable!ChunkLayerSnap(*snap);
				return res;
			}
			else
			{
				return Nullable!ChunkLayerSnap(ChunkLayerSnap.init);
			}
		}

		auto res = Nullable!ChunkLayerSnap.init;
		return res;
	}

	/// Returns writeable copy of current chunk snapshot.
	/// This buffer is valid until commit.
	/// After commit this buffer becomes next immutable snapshot.
	/// Returns null if chunk is not added and/or not loaded.
	/// If write buffer was not yet created then it is created based on policy.
	/// BUG: returned pointer points inside hash table.
	///      If new write buffer is added hash table can reallocate.
	///      Do not use more than one write buffer at a time.
	///      Reallocation can prevent changes to buffers obtained earlier than reallocation to be invisible.
	WriteBuffer* getOrCreateWriteBuffer(ChunkWorldPos cwp, ubyte layer,
		WriteBufferPolicy policy = WriteBufferPolicy.createUniform)
	{
		if (!isChunkLoaded(cwp)) return null;
		auto writeBuffer = cwp in writeBuffers[layer];
		if (writeBuffer is null) {
			writeBuffer = createWriteBuffer(cwp, layer);
			if (writeBuffer && policy == WriteBufferPolicy.copySnapshotArray) {
				auto old = getChunkSnapshot(cwp, layer);
				if (!old.isNull) {
					applyLayer(old, writeBuffer.layer);
				}
			}
		}
		return writeBuffer;
	}

	/// Returns timestamp of current chunk snapshot.
	/// Store this timestamp to use in removeSnapshotUser
	TimestampType addCurrentSnapshotUser(ChunkWorldPos cwp, ubyte layer) {
		auto snap = cwp in snapshots[layer];
		assert(snap, "Cannot add chunk user. No such snapshot.");

		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		assert(state == ChunkState.added_loaded,
			format("To add user chunk must be both added and loaded, not %s", state));

		totalSnapshotUsers[cwp] = totalSnapshotUsers.get(cwp, 0) + 1;

		++snap.numUsers;
		version(TRACE_SNAP_USERS) tracef("#%s:%s (add cur:+1) %s/%s @%s", cwp, layer, snap.numUsers, totalSnapshotUsers[cwp], snap.timestamp);
		return snap.timestamp;
	}

	/// Generic removal of snapshot user. Removes chunk if numUsers == 0.
	/// Use this to remove added snapshot user. Use timestamp returned from addCurrentSnapshotUser.
	void removeSnapshotUser(ChunkWorldPos cwp, TimestampType timestamp, ubyte layer) {
		auto snap = cwp in snapshots[layer];
		if (snap && snap.timestamp == timestamp)
		{
			auto totalUsersLeft = removeCurrentSnapshotUser(cwp, layer);
			if (totalUsersLeft == 0)
			{
				auto state = chunkStates.get(cwp, ChunkState.non_loaded);
				assert(state == ChunkState.added_loaded || state == ChunkState.removed_loaded_used);
				if (state == ChunkState.removed_loaded_used)
				{
					chunkStates[cwp] = ChunkState.non_loaded;
					clearChunkData(cwp);
				}
			}
		}
		else
		{
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
			totalLayerDataBytes += getLayerDataBytes(layer);

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
					assert(false, "On loaded should not occur for non-loading chunk");
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
					chunkStates[cwp] = removed_loaded_used;
				}
				break;
			case added_loading:
				chunkStates[cwp] = added_loaded;
				if (!isSaved) modifiedChunks.put(cwp);
				notifyLoaded(cwp);
				break;
			case removed_loaded_used:
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

		auto cwp = header.cwp;
		auto state = chunkStates.get(header.cwp, ChunkState.non_loaded);
		foreach(i; 0..header.numLayers)
		{
			ChunkLayerTimestampItem layer = chunk.getLayerTimestamp();
			// will delete current chunk when totalUsersLeft becomes 0 and is removed
			removeSnapshotUser(header.cwp, layer.timestamp, layer.layerId);
		}
		mixin(traceStateStr);
	}

	/// called at the end of tick
	void commitSnapshots(TimestampType currentTime) {
		foreach(ubyte layer; 0..numLayers)
		{
			auto writeBuffersCopy = writeBuffers[layer];
			// Clear it here because commit can unload chunk.
			// And unload asserts that chunk is not in writeBuffers.
			writeBuffers[layer] = null;
			foreach(snapshot; writeBuffersCopy.byKeyValue)
			{
				auto cwp = snapshot.key;
				WriteBuffer writeBuffer = snapshot.value;
				if (writeBuffer.isModified)
				{
					modifiedChunks.put(cwp);
					commitLayerSnapshot(cwp, writeBuffer, currentTime, layer);
				}
				else
				{
					if (!writeBuffer.isUniform) {
						freeLayerArray(writeBuffer.layer);
					}
				}
				removeInternalObserver(cwp); // remove user added in createWriteBuffer
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

	private void saveChunk(ChunkWorldPos cwp)
	{
		assert(startChunkSave, "startChunkSave is null");
		assert(pushLayer, "pushLayer is null");
		assert(endChunkSave, "endChunkSave is null");
		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		assert(state == ChunkState.added_loaded, "Save should only occur for added_loaded chunks");

		size_t headerPos = startChunkSave();
		// code lower does work of addCurrentSnapshotUsers too
		ubyte numChunkLayers;
		foreach(ubyte layerId; 0..numLayers)
		{
			if (auto snap = cwp in snapshots[layerId])
			{
				++numChunkLayers;
				++snap.numUsers; // in case new snapshot replaces current one, we need to keep it while it is saved
				pushLayer(ChunkLayerItem(*snap, layerId));
			}
		}
		totalSnapshotUsers[cwp] = totalSnapshotUsers.get(cwp, 0) + numChunkLayers;

		endChunkSave(headerPos, ChunkHeaderItem(cwp, numChunkLayers, 0));
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
			case removed_loaded_used:
				chunkStates[cwp] = added_loaded;
				notifyAdded(cwp);
				notifyLoaded(cwp);
				break;
		}
		mixin(traceStateStr);
	}

	// Puts chunk in removed state requesting save if needed.
	// Notifies on remove.
	private void unloadChunk(ChunkWorldPos cwp) {
		auto state = chunkStates.get(cwp, ChunkState.non_loaded);
		notifyRemoved(cwp);
		with(ChunkState) final switch(state) {
			case non_loaded:
				assert(false, "Unload should not occur when chunk was not yet loaded");
			case added_loaded:
				if(cwp in modifiedChunks)
				{
					modifiedChunks.remove(cwp);
					if (isChunkSavingEnabled)
					{
						saveChunk(cwp);
						chunkStates[cwp] = removed_loaded_used;
					}
				}
				else
				{ // state 0
					auto totalUsersLeft = totalSnapshotUsers.get(cwp, 0);
					if (totalUsersLeft == 0)
					{
						chunkStates[cwp] = non_loaded;
						modifiedChunks.remove(cwp);
						clearChunkData(cwp);
					}
					else
					{
						chunkStates[cwp] = removed_loaded_used;
					}
				}
				break;
			case removed_loading:
				assert(false, "Unload should not occur when chunk is already removed");
			case added_loading:
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
			case removed_loaded_used:
				assert(false, "Unload should not occur when chunk is already removed");
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
	// Latest snapshot's data is not copied in it.
	// Write buffer is then avaliable through getWriteBuffer/getOrCreateWriteBuffer.
	// On commit stage WB is moved into new snapshot if write buffer was modified.
	// Adds internal user that is removed on commit to prevent chunk from unloading with uncommitted changes.
	// Returns pointer to created write buffer.
	private WriteBuffer* createWriteBuffer(ChunkWorldPos cwp, ubyte layer) {
		assert(cwp !in writeBuffers[layer]);
		auto wb = WriteBuffer.init;
		wb.layer.layerId = layer;
		writeBuffers[layer][cwp] = wb;
		addInternalObserver(cwp); // prevent unload until commit
		return cwp in writeBuffers[layer];
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
	private size_t removeCurrentSnapshotUser(ChunkWorldPos cwp, ubyte layer) {
		auto snap = cwp in snapshots[layer];
		assert(snap && snap.numUsers > 0, "cannot remove chunk user. Snapshot has 0 users");

		auto totalUsers = cwp in totalSnapshotUsers;
		assert(totalUsers && (*totalUsers) > 0, "cannot remove chunk user. Snapshot has 0 users");

		--snap.numUsers;
		--(*totalUsers);
		version(TRACE_SNAP_USERS) tracef("#%s:%s (rem cur:-1) %s/%s @%s", cwp, layer, snap.numUsers, totalSnapshotUsers.get(cwp, 0), snap.timestamp);

		if ((*totalUsers) == 0) {
			totalSnapshotUsers.remove(cwp);
			return 0;
		}

		return (*totalUsers);
	}

	// Snapshot is removed from oldSnapshots if numUsers == 0.
	private void removeOldSnapshotUser(ChunkWorldPos cwp, TimestampType timestamp, ubyte layer) {
		ChunkLayerSnap[TimestampType]* chunkSnaps = cwp in oldSnapshots[layer];
		version(TRACE_SNAP_USERS) tracef("#%s:%s (rem old) x/%s @%s", cwp, layer, totalSnapshotUsers.get(cwp, 0), timestamp);
		assert(chunkSnaps, "old snapshot should have waited for releasing user");
		ChunkLayerSnap* snapshot = timestamp in *chunkSnaps;
		assert(snapshot, "cannot release snapshot user. No such snapshot");
		assert(snapshot.numUsers > 0, "cannot remove chunk user. Snapshot has 0 users");
		--snapshot.numUsers;
		version(TRACE_SNAP_USERS) tracef("#%s:%s (rem old:-1) %s/%s @%s", cwp, layer, snapshot.numUsers, totalSnapshotUsers.get(cwp, 0), timestamp);
		if (snapshot.numUsers == 0) {
			(*chunkSnaps).remove(timestamp);
			if ((*chunkSnaps).length == 0) { // all old snaps of one chunk released
				oldSnapshots[layer].remove(cwp);
			}
			recycleSnapshotMemory(*snapshot);
		}
	}

	// Commit for single chunk.
	private void commitLayerSnapshot(ChunkWorldPos cwp, WriteBuffer writeBuffer, TimestampType currentTime, ubyte layer) {
		auto currentSnapshot = getChunkSnapshot(cwp, layer);
		if (!currentSnapshot.isNull) handleCurrentSnapCommit(cwp, layer, currentSnapshot.get());

		assert(writeBuffer.isModified);
		if (writeBuffer.isUniform) {
			if (writeBuffer.layer == ChunkLayerItem.init) {
				snapshots[layer].remove(cwp);
			} else {
				snapshots[layer][cwp] = ChunkLayerSnap(StorageType.uniform, writeBuffer.layer.dataLength,
					currentTime, writeBuffer.layer.uniformData, writeBuffer.layer.metadata);
			}
		} else {
			assert(writeBuffer.layer.type == StorageType.fullArray);
			snapshots[layer][cwp] = ChunkLayerSnap(StorageType.fullArray, currentTime,
				writeBuffer.getArray!ubyte, writeBuffer.layer.metadata);
			totalLayerDataBytes += getLayerDataBytes(writeBuffer.layer);
		}

		assert(isChunkLoaded(cwp), "Commit is only possible for loaded chunk");
	}

	void handleCurrentSnapCommit(ChunkWorldPos cwp, ubyte layer, ChunkLayerSnap currentSnapshot)
	{
		if (currentSnapshot.numUsers == 0) {
			version(TRACE_SNAP_USERS) tracef("#%s:%s (commit:%s) %s/%s @%s", cwp, layer, currentSnapshot.numUsers, 0, totalSnapshotUsers.get(cwp, 0), currentTime);
			recycleSnapshotMemory(currentSnapshot);
		} else {
			// transfer users from current layer snapshot into old snapshot
			auto totalUsers = cwp in totalSnapshotUsers;
			assert(totalUsers && (*totalUsers) >= currentSnapshot.numUsers, "layer has not enough users");
			(*totalUsers) -= currentSnapshot.numUsers;
			if ((*totalUsers) == 0) {
				totalSnapshotUsers.remove(cwp);
			}

			if (auto layerSnaps = cwp in oldSnapshots[layer]) {
				version(TRACE_SNAP_USERS) tracef("#%s:%s (commit add:%s) %s/%s @%s", cwp, layer,
					currentSnapshot.numUsers, 0, totalSnapshotUsers.get(cwp, 0), currentTime);
				assert(currentSnapshot.timestamp !in *layerSnaps);
				(*layerSnaps)[currentSnapshot.timestamp] = currentSnapshot;
			} else {
				version(TRACE_SNAP_USERS) tracef("#%s:%s (commit new:%s) %s/%s @%s", cwp, layer,
					currentSnapshot.numUsers, 0, totalSnapshotUsers.get(cwp, 0), currentTime);
				oldSnapshots[layer][cwp] = [currentSnapshot.timestamp : currentSnapshot];
				version(TRACE_SNAP_USERS) tracef("oldSnapshots[%s][%s] == %s", layer, cwp, oldSnapshots[layer][cwp]);
			}
		}
	}

	// Called when snapshot data can be recycled.
	private void recycleSnapshotMemory(ref ChunkLayerSnap snap) {
		totalLayerDataBytes -= getLayerDataBytes(snap);
		if (snap.type != StorageType.uniform) {
			freeLayerArray(snap);
		}
	}
}


//	TTTTTTT EEEEEEE  SSSSS  TTTTTTT  SSSSS
//	  TTT   EE      SS        TTT   SS
//	  TTT   EEEEE    SSSSS    TTT    SSSSS
//	  TTT   EE           SS   TTT        SS
//	  TTT   EEEEEEE  SSSSS    TTT    SSSSS
//

version(unittest) {
	enum ZERO_CWP = ChunkWorldPos(0, 0, 0, 0);

	private struct Handlers {
		void setup(ChunkManager cm) {
			cm.onChunkAddedHandlers ~= &onChunkAddedHandler;
			cm.onChunkRemovedHandlers ~= &onChunkRemovedHandler;
			cm.onChunkLoadedHandler = &onChunkLoadedHandler;
			cm.loadChunkHandler = &loadChunkHandler;

			cm.startChunkSave = &startChunkSave;
			cm.pushLayer = &pushLayer;
			cm.endChunkSave = &endChunkSave;
		}
		void onChunkAddedHandler(ChunkWorldPos) {
			onChunkAddedHandlerCalled = true;
		}
		void onChunkRemovedHandler(ChunkWorldPos) {
			onChunkRemovedHandlerCalled = true;
		}
		void onChunkLoadedHandler(ChunkWorldPos) {
			onChunkLoadedHandlerCalled = true;
		}
		void loadChunkHandler(ChunkWorldPos cwp) {
			loadChunkHandlerCalled = true;
		}
		size_t startChunkSave() {
			saveChunkHandlerCalled = true;
			return 0;
		}
		void pushLayer(ChunkLayerItem layer) {}
		void endChunkSave(size_t headerPos, ChunkHeaderItem header) {}
		void assertCalled(size_t flags) {
			assert(!(((flags & 0b0000_0001) > 0) ^ onChunkAddedHandlerCalled));
			assert(!(((flags & 0b0000_0010) > 0) ^ onChunkRemovedHandlerCalled));
			assert(!(((flags & 0b0000_0100) > 0) ^ onChunkLoadedHandlerCalled));
			assert(!(((flags & 0b0001_0000) > 0) ^ loadChunkHandlerCalled));
			assert(!(((flags & 0b0010_0000) > 0) ^ saveChunkHandlerCalled));
		}

		bool onChunkAddedHandlerCalled;
		bool onChunkRemovedHandlerCalled;
		bool onChunkLoadedHandlerCalled;
		bool loadChunkHandlerCalled;
		bool saveChunkHandlerCalled;
	}

	private struct TestLoadedChunkData
	{
		ChunkHeaderItem getHeader() { return ChunkHeaderItem(ZERO_CWP, 1, 0); }
		ChunkLayerItem getLayer() { return ChunkLayerItem(); }
	}

	private struct TestSavedChunkData
	{
		TimestampType timestamp;
		ChunkHeaderItem getHeader() {
			return ChunkHeaderItem(ChunkWorldPos(0, 0, 0, 0), 1);
		}
		ChunkLayerTimestampItem getLayerTimestamp() {
			return ChunkLayerTimestampItem(timestamp, 0);
		}
	}

	private struct FSMTester {
		auto ZERO_CWP = ChunkWorldPos(0, 0, 0, 0);
		auto currentState(ChunkManager cm) {
			return cm.chunkStates.get(ZERO_CWP, ChunkState.non_loaded);
		}
		void resetChunk(ChunkManager cm) {
			foreach(layer; 0..cm.numLayers) {
				cm.snapshots[layer].remove(ZERO_CWP);
				cm.oldSnapshots[layer].remove(ZERO_CWP);
				cm.writeBuffers[layer].remove(ZERO_CWP);
			}
			cm.chunkStates.remove(ZERO_CWP);
			cm.modifiedChunks.remove(ZERO_CWP);
			cm.numInternalChunkObservers.remove(ZERO_CWP);
			cm.numExternalChunkObservers.remove(ZERO_CWP);
			cm.totalSnapshotUsers.remove(ZERO_CWP);
		}
		void gotoState(ChunkManager cm, ChunkState state) {
			resetChunk(cm);
			with(ChunkState) final switch(state) {
				case non_loaded:
					break;
				case added_loaded:
					cm.setExternalChunkObservers(ZERO_CWP, 1);
					cm.onSnapshotLoaded(TestLoadedChunkData(), true);
					break;
				case removed_loading:
					cm.setExternalChunkObservers(ZERO_CWP, 1);
					cm.setExternalChunkObservers(ZERO_CWP, 0);
					break;
				case added_loading:
					cm.setExternalChunkObservers(ZERO_CWP, 1);
					break;
				//case removed_loaded_saving:
				//	gotoState(cm, ChunkState.added_loaded_saving);
				//	cm.setExternalChunkObservers(ZERO_CWP, 0);
				//	break;
				case removed_loaded_used:
					gotoState(cm, ChunkState.added_loaded);
					cm.getOrCreateWriteBuffer(ZERO_CWP, FIRST_LAYER, WriteBufferPolicy.copySnapshotArray);
					cm.commitSnapshots(1);
					TimestampType timestamp = cm.addCurrentSnapshotUser(ZERO_CWP, FIRST_LAYER);
					cm.save();
					cm.setExternalChunkObservers(ZERO_CWP, 0);
					cm.onSnapshotSaved(TestSavedChunkData(timestamp));
					break;
				//case added_loaded_saving:
				//	gotoState(cm, ChunkState.added_loaded);
				//	cm.getOrCreateWriteBuffer(ZERO_CWP, FIRST_LAYER);
				//	cm.commitSnapshots(1);
				//	cm.save();
				//	break;
			}
			import std.string : format;
			assert(currentState(cm) == state,
				format("Failed to set state %s, got %s", state, currentState(cm)));
		}

		void gotoStateSaving(ChunkManager cm, ChunkState state)
		{
			if (state == ChunkState.added_loaded)
			{
				gotoState(cm, ChunkState.added_loaded);
				cm.getOrCreateWriteBuffer(ZERO_CWP, FIRST_LAYER, WriteBufferPolicy.copySnapshotArray);
				cm.commitSnapshots(1);
				cm.save();
			}
			else if (state == ChunkState.removed_loaded_used)
			{
				gotoStateSaving(cm, ChunkState.added_loaded);
				cm.setExternalChunkObservers(ZERO_CWP, 0);
			}
			assert(currentState(cm) == state,
				format("Failed to set state %s, got %s", state, currentState(cm)));
		}
	}
}


unittest {
	import voxelman.utils.log : setupLogger;
	setupLogger("test.log");

	Handlers h;
	ChunkManager cm;
	FSMTester fsmTester;

	void assertState(ChunkState state) {
		import std.string : format;
		auto actualState = fsmTester.currentState(cm);
		assert(actualState == state,
			format("Got state '%s', while needed '%s'", actualState, state));
	}

	void assertHasOldSnapshot(TimestampType timestamp) {
		assert(timestamp in cm.oldSnapshots[FIRST_LAYER][ZERO_CWP]);
	}

	void assertNoOldSnapshots() {
		assert(ZERO_CWP !in cm.oldSnapshots[FIRST_LAYER]);
	}

	void assertHasSnapshot() {
		assert(!cm.getChunkSnapshot(ZERO_CWP, FIRST_LAYER).isNull);
	}

	void assertHasNoSnapshot() {
		assert( cm.getChunkSnapshot(ZERO_CWP, FIRST_LAYER).isNull);
	}

	void resetHandlersState() {
		h = Handlers.init;
	}
	void resetChunkManager() {
		cm = new ChunkManager;
		ubyte numLayers = 1;
		cm.setup(numLayers);
		h.setup(cm);
	}
	void reset() {
		resetHandlersState();
		resetChunkManager();
	}

	void setupState(ChunkState state) {
		fsmTester.gotoState(cm, state);
		resetHandlersState();
		assertState(state);
	}

	void setupStateSaving(ChunkState state) {
		fsmTester.gotoStateSaving(cm, state);
		resetHandlersState();
		assertState(state);
	}

	reset();

	//--------------------------------------------------------------------------
	// non_loaded -> added_loading
	cm.setExternalChunkObservers(ZERO_CWP, 1);
	assertState(ChunkState.added_loading);
	assertHasNoSnapshot();
	h.assertCalled(0b0001_0001); //onChunkAddedHandlerCalled, loadChunkHandlerCalled


	//--------------------------------------------------------------------------
	setupState(ChunkState.added_loading);
	// added_loading -> removed_loading
	cm.setExternalChunkObservers(ZERO_CWP, 0);
	assertState(ChunkState.removed_loading);
	assertHasNoSnapshot();
	h.assertCalled(0b0000_0010); //onChunkRemovedHandlerCalled


	//--------------------------------------------------------------------------
	setupState(ChunkState.removed_loading);
	// removed_loading -> added_loading
	cm.setExternalChunkObservers(ZERO_CWP, 1);
	assertState(ChunkState.added_loading);
	assertHasNoSnapshot();
	h.assertCalled(0b0000_0001); //onChunkAddedHandlerCalled


	//--------------------------------------------------------------------------
	setupState(ChunkState.removed_loading);
	// removed_loading -> non_loaded
	cm.onSnapshotLoaded(TestLoadedChunkData(), true);
	assertState(ChunkState.non_loaded);
	assertHasNoSnapshot();
	h.assertCalled(0b0000_0000);

	//--------------------------------------------------------------------------
	setupState(ChunkState.added_loading);
	// added_loading -> added_loaded + modified
	cm.onSnapshotLoaded(TestLoadedChunkData(), false);
	assertState(ChunkState.added_loaded);
	assertHasSnapshot();
	h.assertCalled(0b0000_0100); //onChunkLoadedHandlerCalled
	assert(ZERO_CWP in cm.modifiedChunks);

	//--------------------------------------------------------------------------
	setupState(ChunkState.added_loading);
	// added_loading -> added_loaded
	cm.onSnapshotLoaded(TestLoadedChunkData(), true);
	assertState(ChunkState.added_loaded);
	assertHasSnapshot();
	h.assertCalled(0b0000_0100); //onChunkLoadedHandlerCalled
	assert(ZERO_CWP !in cm.modifiedChunks);

	//--------------------------------------------------------------------------
	setupState(ChunkState.added_loaded);
	// added_loaded -> non_loaded
	cm.setExternalChunkObservers(ZERO_CWP, 0);
	assertState(ChunkState.non_loaded);
	h.assertCalled(0b0000_0010); //onChunkRemovedHandlerCalled

	//--------------------------------------------------------------------------
	setupState(ChunkState.added_loaded);
	// added_loaded -> removed_loaded_used
	cm.getOrCreateWriteBuffer(ZERO_CWP, FIRST_LAYER, WriteBufferPolicy.copySnapshotArray);
	cm.commitSnapshots(TimestampType(1));
	cm.setExternalChunkObservers(ZERO_CWP, 0);
	assertState(ChunkState.removed_loaded_used);
	h.assertCalled(0b0010_0010); //onChunkRemovedHandlerCalled, loadChunkHandlerCalled

	//--------------------------------------------------------------------------
	setupState(ChunkState.added_loaded);
	// added_loaded -> added_loaded
	cm.getOrCreateWriteBuffer(ZERO_CWP, FIRST_LAYER, WriteBufferPolicy.copySnapshotArray);
	cm.commitSnapshots(TimestampType(1));
	cm.save();
	assertState(ChunkState.added_loaded);
	h.assertCalled(0b0010_0000); //loadChunkHandlerCalled

	//--------------------------------------------------------------------------
	setupState(ChunkState.added_loaded);
	// added_loaded with user -> added_loaded no user after commit
	cm.addCurrentSnapshotUser(ZERO_CWP, FIRST_LAYER);
	cm.getOrCreateWriteBuffer(ZERO_CWP, FIRST_LAYER, WriteBufferPolicy.copySnapshotArray);
	cm.commitSnapshots(TimestampType(1));
	assertState(ChunkState.added_loaded);
	h.assertCalled(0b0000_0000);
	assertHasOldSnapshot(TimestampType(0));

	//--------------------------------------------------------------------------
	setupStateSaving(ChunkState.added_loaded);
	// added_loaded saving -> added_loaded after on_saved
	cm.onSnapshotSaved(TestSavedChunkData(TimestampType(1)));
	assertState(ChunkState.added_loaded);
	h.assertCalled(0b0000_0000);

	//--------------------------------------------------------------------------
	setupStateSaving(ChunkState.added_loaded);
	// added_loaded saving -> removed_loaded saving
	cm.setExternalChunkObservers(ZERO_CWP, 0);
	assertState(ChunkState.removed_loaded_used);
	h.assertCalled(0b0000_0010); //onChunkRemovedHandlerCalled


	//--------------------------------------------------------------------------
	setupStateSaving(ChunkState.removed_loaded_used);
	// removed_loaded_used saving -> non_loaded
	cm.onSnapshotSaved(TestSavedChunkData(TimestampType(1)));
	assertState(ChunkState.non_loaded);
	h.assertCalled(0b0000_0000);

	//--------------------------------------------------------------------------
	setupStateSaving(ChunkState.added_loaded);
	// removed_loaded_used saving -> removed_loaded_used
	cm.addCurrentSnapshotUser(ZERO_CWP, FIRST_LAYER);
	cm.setExternalChunkObservers(ZERO_CWP, 0);
	assertState(ChunkState.removed_loaded_used); // & saving
	cm.onSnapshotSaved(TestSavedChunkData(TimestampType(1)));
	assertState(ChunkState.removed_loaded_used);
	h.assertCalled(0b0000_0010); //onChunkRemovedHandlerCalled

	//--------------------------------------------------------------------------
	setupStateSaving(ChunkState.removed_loaded_used);
	// removed_loaded_used saving -> added_loaded saving
	cm.setExternalChunkObservers(ZERO_CWP, 1);
	assertState(ChunkState.added_loaded);
	h.assertCalled(0b0000_0101); //onChunkAddedHandlerCalled, onChunkLoadedHandlerCalled

	//--------------------------------------------------------------------------
	setupState(ChunkState.removed_loaded_used);
	// removed_loaded_used -> non_loaded
	cm.removeSnapshotUser(ZERO_CWP, TimestampType(1), FIRST_LAYER);
	assertState(ChunkState.non_loaded);
	h.assertCalled(0b0000_0000);


	//--------------------------------------------------------------------------
	setupState(ChunkState.removed_loaded_used);
	// removed_loaded_used -> added_loaded
	cm.setExternalChunkObservers(ZERO_CWP, 1);
	assertState(ChunkState.added_loaded);
	h.assertCalled(0b0000_0101); //onChunkAddedHandlerCalled, onChunkLoadedHandlerCalled


	//--------------------------------------------------------------------------
	// test unload of old chunk when it has users. No prev snapshots for given pos.
	setupState(ChunkState.added_loaded);
	TimestampType timestamp = cm.addCurrentSnapshotUser(ZERO_CWP, FIRST_LAYER);
	assert(timestamp == TimestampType(0));
	cm.getOrCreateWriteBuffer(ZERO_CWP, FIRST_LAYER, WriteBufferPolicy.copySnapshotArray);
	cm.commitSnapshots(1);
	assert(timestamp in cm.oldSnapshots[FIRST_LAYER][ZERO_CWP]);
	cm.removeSnapshotUser(ZERO_CWP, timestamp, FIRST_LAYER);
	assertNoOldSnapshots();

	//--------------------------------------------------------------------------
	// test unload of old chunk when it has users. Already has snapshot for earlier timestamp.
	setupState(ChunkState.added_loaded);

	TimestampType timestamp0 = cm.addCurrentSnapshotUser(ZERO_CWP, FIRST_LAYER);
	cm.getOrCreateWriteBuffer(ZERO_CWP, FIRST_LAYER, WriteBufferPolicy.copySnapshotArray);
	cm.commitSnapshots(1); // commit adds timestamp 0 to oldSnapshots
	assert(timestamp0 in cm.oldSnapshots[FIRST_LAYER][ZERO_CWP]);

	TimestampType timestamp1 = cm.addCurrentSnapshotUser(ZERO_CWP, FIRST_LAYER);
	cm.getOrCreateWriteBuffer(ZERO_CWP, FIRST_LAYER, WriteBufferPolicy.copySnapshotArray);
	cm.commitSnapshots(2); // commit adds timestamp 1 to oldSnapshots
	assert(timestamp1 in cm.oldSnapshots[FIRST_LAYER][ZERO_CWP]);

	cm.removeSnapshotUser(ZERO_CWP, timestamp0, FIRST_LAYER);
	cm.removeSnapshotUser(ZERO_CWP, timestamp1, FIRST_LAYER);
	assertNoOldSnapshots();

	//--------------------------------------------------------------------------
	// test case where old snapshot was saved and current snapshot is added_loaded
	setupState(ChunkState.added_loaded);
	cm.getOrCreateWriteBuffer(ZERO_CWP, FIRST_LAYER, WriteBufferPolicy.copySnapshotArray);
	cm.commitSnapshots(1);
	cm.save();
	cm.getOrCreateWriteBuffer(ZERO_CWP, FIRST_LAYER, WriteBufferPolicy.copySnapshotArray);
	cm.commitSnapshots(2); // now, snap that is saved is old.
	cm.onSnapshotSaved(TestSavedChunkData(TimestampType(1)));
	assertNoOldSnapshots();
}
