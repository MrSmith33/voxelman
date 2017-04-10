/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.chunk.manager;

import voxelman.log;
import std.typecons : Nullable;
import std.string : format;
public import std.typecons : Flag, Yes, No;

import voxelman.container.multihashset;
import voxelman.container.hash.set;
import voxelman.world.block;
import voxelman.core.config;
import voxelman.world.storage.chunk;
import voxelman.world.storage.coordinates : ChunkWorldPos, adjacentPositions;
import voxelman.world.storage.utils;
import voxelman.world.storage.chunk.chunkprovider;


private enum ChunkState {
	non_loaded,
	added_loaded,
	added_loading,
	removed_loaded_used
}

private enum traceStateStr = q{
	//infof("state @%s %s => %s", cwp, state,
	//	chunkStates.get(cwp, ChunkState.non_loaded));
};


struct AdjChunkPositions27 {
	this(ChunkWorldPos cwp) {
		central = cwp;
		adjacentPositions!26(cwp, adjacent26);
	}
	union {
		ChunkWorldPos[27] all;
		ChunkWorldPos[26] adjacent26;
		struct {
			ChunkWorldPos[6] adjacent6;
			ChunkWorldPos[20] adjacent20;
			ChunkWorldPos central;
		}
	}
}

struct AdjChunkLayers27 {
	union {
		Nullable!ChunkLayerSnap[27] all;
		Nullable!ChunkLayerSnap[26] adjacent26;
		struct {
			Nullable!ChunkLayerSnap[6] adjacent6;
			Nullable!ChunkLayerSnap[20] adjacent20;
			Nullable!ChunkLayerSnap central;
		}
	}
}

Nullable!ChunkLayerSnap[len] getChunkSnapshots
	(size_t len)
	(ChunkManager cm,
	ChunkWorldPos[len] positions,
	ubyte layer,
	Flag!"Uncompress" uncompress = No.Uncompress)
{
	typeof(return) result;

	foreach(i, cwp; positions)
	{
		result[i] = cm.getChunkSnapshot(cwp, layer, uncompress);
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

struct ChunkLayerInfo
{
	/// Defines the size of
	LayerDataLenType uniformExpansionType;
}

struct ModifiedChunksRange
{
	private HashSet!ChunkWorldPos modifiedChunks;
	int opApply(scope int delegate(in ChunkWorldPos) del) {
		return modifiedChunks.opApply(del);
	}
}

enum MAX_CHUNK_LAYERS = 8;

final class ChunkManager {
	void delegate(ChunkWorldPos) onChunkRemovedHandler;
	void delegate(ChunkWorldPos) onChunkLoadedHandler;

	void delegate(ChunkWorldPos) loadChunkHandler;
	void delegate(ChunkWorldPos) saveChunkHandler;
	void delegate(ChunkWorldPos) cancelLoadChunkHandler;

	// debug
	long totalLayerDataBytes;
	long numLoadedChunks;
	size_t numTrackedChunks() { return chunkStates.length; }

	private ChunkLayerSnap[ChunkWorldPos][] snapshots;
	private ChunkLayerSnap[TimestampType][ChunkWorldPos][] oldSnapshots;
	private ChunkState[ChunkWorldPos] chunkStates;
	private HashSet!ChunkWorldPos modifiedChunks;
	// used to change state from added_loaded to removed_loaded_used
	private MultiHashSet!ChunkWorldPos totalSnapshotUsers;


	ubyte numLayers;
	package ChunkLayerInfo[] layerInfos;

	this(ubyte _numLayers) {
		numLayers = _numLayers;
		snapshots.length = numLayers;
		oldSnapshots.length = numLayers;
		layerInfos.length = numLayers;
	}

	void setLayerInfo(ubyte layer, ChunkLayerInfo info) {
		layerInfos[layer] = info;
	}

	bool areChunksLoaded(ChunkWorldPos[] positions) {
		foreach(pos; positions)
			if (!isChunkLoaded(pos))
				return false;
		return true;
	}

	bool isChunkLoaded(ChunkWorldPos cwp) {
		return getChunkState(cwp) == ChunkState.added_loaded;
	}

	bool isChunkAdded(ChunkWorldPos cwp) {
		auto state = getChunkState(cwp);
		with(ChunkState) {
			return state == added_loaded || state == added_loading;
		}
	}

	bool hasSnapshot(ChunkWorldPos cwp, ubyte layer) {
		return (cwp in snapshots[layer]) !is null;
	}

	ModifiedChunksRange getModifiedChunks() {
		return ModifiedChunksRange(modifiedChunks);
	}

	/// Used on client to clear modified chunks instead of saving them.
	void clearModifiedChunks() {
		modifiedChunks.clear();
	}

	/// returned value isNull if chunk is not loaded/added
	/// If uncompress is Yes then tries to convert snapshot to uncompressed.
	/// If has users, then uncompressed snapshot copy is returned. Original will not be uncompressed.
	Nullable!ChunkLayerSnap getChunkSnapshot(ChunkWorldPos cwp, ubyte layer, Flag!"Uncompress" uncompress = No.Uncompress) {
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
						totalLayerDataBytes += snap.dataLength;
						snap.type = StorageType.fullArray;
					}
					else
					{
						// BUG: memory leak
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
				auto res = ChunkLayerSnap.init;
				res.dataLength = layerInfos[layer].uniformExpansionType;
				return Nullable!ChunkLayerSnap(res);
			}
		}

		auto res = Nullable!ChunkLayerSnap.init;
		return res;
	}

	/// Returns timestamp of current chunk snapshot.
	/// Store this timestamp to use in removeSnapshotUser
	/// Adding a user to non-existent snapshot of loaded chunk is allowed,
	/// since a ChunkLayerSnap.init is returned for such layer.
	/// Special TimestampType.max is returned.
	TimestampType addCurrentSnapshotUser(ChunkWorldPos cwp, ubyte layer) {
		auto snap = cwp in snapshots[layer];
		if (!snap)
		{
			return TimestampType.max;
		}
		version(TRACE_SNAP_USERS) tracef("#%s:%s (before add) %s/%s", cwp, layer, snap.numUsers, totalSnapshotUsers[cwp]);

		auto state = getChunkState(cwp);
		assert(state == ChunkState.added_loaded,
			format("To add user chunk must be both added and loaded, not %s", state));

		totalSnapshotUsers.add(cwp);

		++snap.numUsers;
		version(TRACE_SNAP_USERS) tracef("#%s:%s (add cur:+1) %s/%s @%s", cwp, layer, snap.numUsers, totalSnapshotUsers[cwp], snap.timestamp);
		return snap.timestamp;
	}

	/// Generic removal of snapshot user. Removes chunk if numUsers == 0.
	/// Use this to remove added snapshot user. Use timestamp returned from addCurrentSnapshotUser.
	/// Removing TimestampType.max is no-op.
	void removeSnapshotUser(ChunkWorldPos cwp, TimestampType timestamp, ubyte layer) {
		if (timestamp == TimestampType.max) return;
		auto snap = cwp in snapshots[layer];
		if (snap && snap.timestamp == timestamp)
		{
			auto totalUsersLeft = removeCurrentSnapshotUser(cwp, layer);
			if (totalUsersLeft == 0)
			{
				auto state = getChunkState(cwp);
				assert(state == ChunkState.added_loaded || state == ChunkState.removed_loaded_used);
				if (state == ChunkState.removed_loaded_used)
				{
					clearChunkData(cwp);
					--numLoadedChunks;
				}
			}
		}
		else
		{
			removeOldSnapshotUser(cwp, timestamp, layer);
		}
	}

	private struct SnapshotIterator
	{
		private ChunkLayerSnap[ChunkWorldPos][] snapshots;
		private ubyte numLayers;
		private ChunkWorldPos cwp;
		private MultiHashSet!ChunkWorldPos* totalSnapshotUsers;
		int opApply(scope int delegate(ChunkLayerItem) del) {
			ubyte numChunkLayers;
			foreach(ubyte layerId; 0..numLayers)
			{
				if (auto snap = cwp in snapshots[layerId])
				{
					++snap.numUsers; // in case new snapshot replaces current one, we need to keep it while it is saved
					totalSnapshotUsers.add(cwp);
					if (auto ret = del(ChunkLayerItem(*snap, layerId)))
						return ret;
				}
			}

			return 0;
		}
	}

	SnapshotIterator iterateChunkSnapshotsAddUsers(ChunkWorldPos cwp) {
		return SnapshotIterator(snapshots, numLayers, cwp, &totalSnapshotUsers);
	}

	/// Internal. Called by code which loads chunks from storage.
	void onSnapshotLoaded(ChunkWorldPos cwp, ChunkLayerItem[] layers, bool markAsModified) {
		version(DBG_OUT)infof("res loaded %s", cwp);

		foreach(layer; layers)
		{
			totalLayerDataBytes += getLayerDataBytes(layer);

			snapshots[layer.layerId][cwp] = ChunkLayerSnap(layer);
			version(DBG_COMPR)if (layer.type == StorageType.compressedArray)
				infof("CM Loaded %s %s %s\n(%(%02x%))", cwp, layer.dataPtr, layer.dataLength, layer.getArray!ubyte);
		}

		auto state = getChunkState(cwp);

		with(ChunkState) final switch(state)
		{
			case non_loaded:
				clearChunkData(cwp);
				break;
			case added_loaded:
				assert(false, "On loaded should not occur for already loaded chunk");
			case added_loading:
				chunkStates[cwp] = added_loaded;
				++numLoadedChunks;
				if (markAsModified) modifiedChunks.put(cwp);
				notifyLoaded(cwp);
				break;
			case removed_loaded_used:
				assert(false, "On loaded should not occur for already loaded chunk");
		}
		mixin(traceStateStr);
	}

	// Puts chunk in added state requesting load if needed.
	// Notifies on add. Notifies on load if loaded.
	void loadChunk(ChunkWorldPos cwp) {
		auto state = getChunkState(cwp);
		with(ChunkState) final switch(state) {
			case non_loaded:
				chunkStates[cwp] = added_loading;
				if (loadChunkHandler) loadChunkHandler(cwp);
				break;
			case added_loaded:
				break; // ignore
			case added_loading:
				break; // ignore
			case removed_loaded_used:
				chunkStates[cwp] = added_loaded;
				notifyLoaded(cwp);
				break;
		}
		mixin(traceStateStr);
	}

	// Puts chunk in removed state requesting save if needed.
	// Notifies on remove.
	void unloadChunk(ChunkWorldPos cwp) {
		auto state = getChunkState(cwp);
		notifyRemoved(cwp);
		with(ChunkState) final switch(state) {
			case non_loaded:
				assert(false, "Unload should not occur when chunk was not yet loaded");
			case added_loaded:
				if(cwp in modifiedChunks)
				{
					modifiedChunks.remove(cwp);
					if (saveChunkHandler) saveChunkHandler(cwp);
				}
				else
				{
					auto totalUsersLeft = totalSnapshotUsers[cwp];
					if (totalUsersLeft == 0)
					{
						clearChunkData(cwp);
						--numLoadedChunks;
					}
					else
					{
						chunkStates[cwp] = removed_loaded_used;
					}
				}
				break;
			case added_loading:
				if (cancelLoadChunkHandler) cancelLoadChunkHandler(cwp);
				clearChunkData(cwp);
				break;
			case removed_loaded_used:
				assert(false, "Unload should not occur when chunk is already removed");
		}
		mixin(traceStateStr);
	}

	// Commit for single chunk.
	void commitLayerSnapshot(ChunkWorldPos cwp, WriteBuffer writeBuffer, TimestampType currentTime, ubyte layer) {
		modifiedChunks.put(cwp);

		auto currentSnapshot = getChunkSnapshot(cwp, layer);
		if (!currentSnapshot.isNull) handleCurrentSnapCommit(cwp, layer, currentSnapshot.get());

		assert(writeBuffer.isModified);

		if (writeBuffer.removeSnapshot)
		{
			freeLayerArray(writeBuffer.layer);
			snapshots[layer].remove(cwp);
			return;
		}

		writeBuffer.layer.timestamp = currentTime;
		snapshots[layer][cwp] = ChunkLayerSnap(writeBuffer.layer);
		totalLayerDataBytes += getLayerDataBytes(writeBuffer.layer);

		if (!isChunkLoaded(cwp)) {
			chunkStates[cwp] = ChunkState.added_loaded;
			// BUG/TODO: this will be called on first write buffer, while needs to be called on last write buffer
			notifyLoaded(cwp);
		}
	}

	//	PPPPPP  RRRRRR  IIIII VV     VV   AAA   TTTTTTT EEEEEEE
	//	PP   PP RR   RR  III  VV     VV  AAAAA    TTT   EE
	//	PPPPPP  RRRRRR   III   VV   VV  AA   AA   TTT   EEEEE
	//	PP      RR  RR   III    VV VV   AAAAAAA   TTT   EE
	//	PP      RR   RR IIIII    VVV    AA   AA   TTT   EEEEEEE
	//

	private void notifyRemoved(ChunkWorldPos cwp) {
		if (onChunkRemovedHandler) onChunkRemovedHandler(cwp);
	}

	private void notifyLoaded(ChunkWorldPos cwp) {
		if (onChunkLoadedHandler) onChunkLoadedHandler(cwp);
	}

	private ChunkState getChunkState(ChunkWorldPos cwp) {
		return chunkStates.get(cwp, ChunkState.non_loaded);
	}

	// Fully removes chunk
	private void clearChunkData(ChunkWorldPos cwp) {
		foreach(layer; 0..numLayers)
		{
			if (auto snap = cwp in snapshots[layer])
			{
				recycleSnapshotMemory(*snap);
				snapshots[layer].remove(cwp);
			}
			assert(totalSnapshotUsers[cwp] == 0);
		}
		assert(cwp !in modifiedChunks);
		chunkStates.remove(cwp);
	}

	// Returns number of current snapshot users left.
	private size_t removeCurrentSnapshotUser(ChunkWorldPos cwp, ubyte layer) {
		auto snap = cwp in snapshots[layer];
		assert(snap && snap.numUsers > 0, "cannot remove chunk user. Snapshot has 0 users");

		version(TRACE_SNAP_USERS) tracef("#%s:%s (rem before) %s/%s", cwp, layer, snap.numUsers, totalSnapshotUsers[cwp]);

		--snap.numUsers;
		assert(totalSnapshotUsers[cwp] > 0, "cannot remove chunk user. Snapshot has 0 users");
		totalSnapshotUsers.remove(cwp);

		version(TRACE_SNAP_USERS) tracef("#%s:%s (rem cur:-1) %s/%s @%s", cwp, layer, snap.numUsers, totalSnapshotUsers[cwp], snap.timestamp);

		return totalSnapshotUsers[cwp];
	}

	/// Snapshot is removed from oldSnapshots if numUsers == 0.
	private void removeOldSnapshotUser(ChunkWorldPos cwp, TimestampType timestamp, ubyte layer) {
		ChunkLayerSnap[TimestampType]* chunkSnaps = cwp in oldSnapshots[layer];
		version(TRACE_SNAP_USERS) tracef("#%s:%s (rem old) x/%s @%s", cwp, layer, totalSnapshotUsers[cwp], timestamp);
		assert(chunkSnaps, "old snapshot should have waited for releasing user");
		ChunkLayerSnap* snapshot = timestamp in *chunkSnaps;
		assert(snapshot, "cannot release snapshot user. No such snapshot");
		assert(snapshot.numUsers > 0, "cannot remove chunk user. Snapshot has 0 users");
		--snapshot.numUsers;
		version(TRACE_SNAP_USERS) tracef("#%s:%s (rem old:-1) %s/%s @%s", cwp, layer, snapshot.numUsers, totalSnapshotUsers[cwp], timestamp);
		if (snapshot.numUsers == 0) {
			(*chunkSnaps).remove(timestamp);
			if ((*chunkSnaps).length == 0) { // all old snaps of one chunk released
				oldSnapshots[layer].remove(cwp);
			}
			recycleSnapshotMemory(*snapshot);
		}
	}

	private void handleCurrentSnapCommit(ChunkWorldPos cwp, ubyte layer, ChunkLayerSnap currentSnapshot)
	{
		if (currentSnapshot.numUsers == 0) {
			version(TRACE_SNAP_USERS) tracef("#%s:%s (commit:%s) %s/%s", cwp, layer, currentSnapshot.numUsers, 0, totalSnapshotUsers[cwp]);
			recycleSnapshotMemory(currentSnapshot);
		} else {
			// transfer users from current layer snapshot into old snapshot
			totalSnapshotUsers.remove(cwp, currentSnapshot.numUsers);

			if (auto layerSnaps = cwp in oldSnapshots[layer]) {
				version(TRACE_SNAP_USERS) tracef("#%s:%s (commit add:%s) %s/%s", cwp, layer,
					currentSnapshot.numUsers, 0, totalSnapshotUsers[cwp]);
				assert(currentSnapshot.timestamp !in *layerSnaps);
				(*layerSnaps)[currentSnapshot.timestamp] = currentSnapshot;
			} else {
				version(TRACE_SNAP_USERS) tracef("#%s:%s (commit new:%s) %s/%s", cwp, layer,
					currentSnapshot.numUsers, 0, totalSnapshotUsers[cwp]);
				oldSnapshots[layer][cwp] = [currentSnapshot.timestamp : currentSnapshot];
				version(TRACE_SNAP_USERS) tracef("oldSnapshots[%s][%s] == %s", layer, cwp, oldSnapshots[layer][cwp]);
			}
		}
	}

	// Called when snapshot data can be recycled.
	private void recycleSnapshotMemory(ref ChunkLayerSnap snap) {
		totalLayerDataBytes -= getLayerDataBytes(snap);
		freeLayerArray(snap);
	}
}

