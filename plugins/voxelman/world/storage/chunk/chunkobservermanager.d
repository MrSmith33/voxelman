/**
Copyright: Copyright (c) 2015-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.chunk.chunkobservermanager;

import voxelman.container.buffer;
import voxelman.log;
import voxelman.math;
import voxelman.core.config : DimensionId;
import netlib : SessionId;
import voxelman.world.storage.coordinates : ChunkWorldPos;
import voxelman.world.storage.worldbox : WorldBox, TrisectResult,
	trisect4d, calcBox, shiftAndClampBoxByBorders;


// Manages lists of observers per chunk
final class ChunkObserverManager {
	void delegate(ChunkWorldPos) loadChunkHandler;
	void delegate(ChunkWorldPos) unloadChunkHandler;
	void delegate(ChunkWorldPos, SessionId) chunkObserverAddedHandler;

	private ChunkObservers[ChunkWorldPos] chunkObservers;
	ViewBoxes viewBoxes;

	void update() {

	}

	SessionId[] getChunkObservers(ChunkWorldPos cwp) {
		return chunkObservers.get(cwp, ChunkObservers.init).clients;
	}

	void addServerObserverBox(WorldBox box, Box dimBorders) {
		WorldBox boundedBox = shiftAndClampBoxByBorders(box, dimBorders);
		foreach(ChunkWorldPos cwp; boundedBox)
			addServerObserver(cwp);
	}

	void removeServerObserverBox(WorldBox box, Box dimBorders) {
		WorldBox boundedBox = shiftAndClampBoxByBorders(box, dimBorders);
		foreach(ChunkWorldPos cwp; boundedBox)
			removeServerObserver(cwp);
	}

	void addServerObserver(ChunkWorldPos cwp) {
		auto list = chunkObservers.get(cwp, ChunkObservers.init);
		++list.numServerObservers;
		onChunkNumObserversChanged(cwp, list.numObservers);
		chunkObservers[cwp] = list;
	}

	void removeServerObserver(ChunkWorldPos cwp) {
		auto list = chunkObservers.get(cwp, ChunkObservers.init);
		--list.numServerObservers;
		onChunkNumObserversChanged(cwp, list.numObservers);
		if (list.empty)
			chunkObservers.remove(cwp);
		else
			chunkObservers[cwp] = list;
	}

	void removeObserver(SessionId sessionId) {
		changeObserverBox(sessionId, WorldBox());
	}

	void changeObserverBox(SessionId sessionId, ChunkWorldPos observerPosition, int viewRadius, Box dimBorders) {
		WorldBox newBox = calcBox(observerPosition, viewRadius);
		WorldBox boundedBox = shiftAndClampBoxByBorders(newBox, dimBorders);
		changeObserverBox(sessionId, boundedBox);
	}

	void changeObserverBox(SessionId sessionId, WorldBox newBox) {
		WorldBox oldBox = viewBoxes[sessionId];

		if (newBox == oldBox)
			return;

		TrisectResult tsect = trisect4d(oldBox, newBox);

		// remove observer
		foreach(a; tsect.aPositions) {
			removeChunkObserver(ChunkWorldPos(a, oldBox.dimension), sessionId);
		}

		// add observer
		foreach(b; tsect.bPositions) {
			addChunkObserver(ChunkWorldPos(b, newBox.dimension), sessionId);
		}

		viewBoxes[sessionId] = newBox;
	}

	private bool addChunkObserver(ChunkWorldPos cwp, SessionId sessionId) {
		auto list = chunkObservers.get(cwp, ChunkObservers.init);
		if (list.add(sessionId)) {
			onChunkNumObserversChanged(cwp, list.numObservers);
			chunkObserverAddedHandler(cwp, sessionId);
			chunkObservers[cwp] = list;
			return true;
		}
		return false;
	}

	private void removeChunkObserver(ChunkWorldPos cwp, SessionId sessionId) {
		auto list = chunkObservers.get(cwp, ChunkObservers.init);
		bool removed = list.remove(sessionId);
		if (removed)
			onChunkNumObserversChanged(cwp, list.numObservers);
		if (list.empty)
			chunkObservers.remove(cwp);
		else
			chunkObservers[cwp] = list;
	}

	// Here comes sum of all internal and external chunk users which results in loading or unloading of specific chunk.
	private void onChunkNumObserversChanged(ChunkWorldPos cwp, size_t numObservers) {
		if (numObservers > 0) {
			loadChunkHandler(cwp);
		} else {
			unloadChunkHandler(cwp);
		}
	}
}

private struct ViewBoxes
{
	private WorldBox[SessionId] viewInfos;

	WorldBox opIndex(SessionId sessionId) {
		return viewInfos.get(sessionId, WorldBox.init);
	}

	void opIndexAssign(WorldBox newBox, SessionId sessionId) {
		if (newBox.empty)
			viewInfos.remove(sessionId);
		else
			viewInfos[sessionId] = newBox;
	}
}

// Describes observers for a single chunk
private struct ChunkObservers {
	import std.algorithm : canFind, countUntil;

	// clients observing this chunk
	private SessionId[] _clients;
	// Each client can observe a chunk multiple times via multiple boxes.
	private size_t[] numObservations;
	// ref counts for keeping chunk loaded
	size_t numServerObservers;

	SessionId[] clients() @property {
		return _clients;
	}

	bool empty() @property const {
		return numObservers == 0;
	}

	size_t numObservers() @property const {
		return _clients.length + numServerObservers;
	}

	bool contains(SessionId sessionId) const {
		return canFind(_clients, sessionId);
	}

	// returns true if sessionId was not in clients already
	bool add(SessionId sessionId)	{
		auto index = countUntil(_clients, sessionId);
		if (index == -1) {
			_clients ~= sessionId;
			numObservations ~= 1;
			return true;
		} else {
			++numObservations[index];
			return false;
		}
	}

	// returns true if sessionId is no longer in list (has zero observations)
	bool remove(SessionId sessionId)
	{
		auto index = countUntil(_clients, sessionId);
		if (index == -1)
		{
			return false;
		}
		else
		{
			--numObservations[index];
			if (numObservations[index] == 0)
			{
				numObservations[index] = numObservations[$-1];
				numObservations = numObservations[0..$-1];
				_clients[index] = _clients[$-1];
				_clients = _clients[0..$-1];

				return true;
			}
			else
			{
				return false;
			}
		}
	}
}
