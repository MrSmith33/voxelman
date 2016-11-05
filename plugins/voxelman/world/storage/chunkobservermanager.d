/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.chunkobservermanager;

import voxelman.container.buffer;
import voxelman.log;
import voxelman.math;
import voxelman.core.config : DimensionId;
import netlib : SessionId;
import voxelman.world.storage.coordinates : ChunkWorldPos;
import voxelman.world.storage.worldbox : WorldBox, TrisectResult, trisect4d, calcBox;

enum chunkPackLoadSize = 200;

struct ViewInfo
{
	WorldBox viewBox;
	//ivec3 viewRadius;
	//ChunkWorldPos observerPosition;
	//int viewRadius;

	//size_t numObservedRings;
	//size_t currentChunkIndex;
}

// Manages lists of observers per chunk
final class ChunkObserverManager {
	void delegate(ChunkWorldPos, size_t numObservers) changeChunkNumObservers;
	void delegate(ChunkWorldPos, SessionId) chunkObserverAdded;
	size_t delegate() loadQueueSpaceAvaliable;

	private ChunkObservers[ChunkWorldPos] chunkObservers;
	private ViewInfo[SessionId] viewInfos;

	void update() {

	}
	string a = q{

		import std.algorithm : sort;

		if (viewInfos.length == 0)
			return;

		ViewInfo[] infos = viewInfos.values;
		size_t chunksObserved;

		infinite_loop:
		while (true)
		{
			sort!((a, b) => a.numObservedRings < b.numObservedRings)(infos);
			chunksObserved = 0;

			foreach(ref info; infos)
			{
				immutable size_t currentRing = info.numObservedRings;
				// fully loaded
				// TODO
				assert(false, "fix viewRadius usage");
				if (currentRing > info.viewRadius)
					break;

				//infof("For infos C:%s VR:%s OR:%s CI:%s", info.sessionId, info.viewRadius,
				//	info.numObservedRings, info.currentChunkIndex);

				size_t chunksToLoadClient = chunkPackLoadSize;

				immutable ivec3 observerPosition = info.observerPosition;
				immutable size_t sideSize = currentRing * 2 + 1;
				immutable size_t sideMax = sideSize - 1;
				immutable size_t sideSizeSqr = sideSize * sideSize;
				immutable size_t numIndexes = sideSizeSqr * sideSize;
				//infof("numIndexes %s sideSize %s", numIndexes, sideSize);

				size_t index = info.currentChunkIndex;
				ivec3 position;
				bool empty() {
					return index == numIndexes;
				}
				// returns true if no positions left
				bool popFront() {
					size_t x, y, z;
					while(true) {
						if (index == numIndexes)
							return true;

						x = index % sideSize;
						y = (index / sideSizeSqr) % sideSize;
						z = (index / sideSize) % sideSize;
						++index;

						if (x == 0 || y == 0 || z == 0 ||
							x == sideMax || y == sideMax || z == sideMax)
							break;
					}
					position = ivec3(x, y, z) + observerPosition - ivec3(currentRing, currentRing, currentRing);
					//infof("popFront %s %s index %s", position, ivec3(x, y, z), index-1);
					return false;
				}

				while (true) {
					bool stop = empty();
					if (stop) {// ring end
						//infof("Ring %s loaded for C:%s", info.numObservedRings, info.sessionId);
						++info.numObservedRings;
						info.currentChunkIndex = 0;
						break;
					}
					popFront();

					bool added = addChunkObserver(ChunkWorldPos(position), info.sessionId);

					if (added) {
						//infof("Add %s", position);

						--chunksToLoadClient;
						++chunksObserved;

						if (loadQueueSpaceAvaliable() == 0)
							break infinite_loop;
						if (chunksToLoadClient == 0)
							break;
					}
				}
			}
			// nothing to update
			if (chunksObserved == 0)
				break infinite_loop;
			//else
			//	infof("Observed %s chunks", chunksObserved);
		}

		foreach(info; infos) {
			viewInfos[info.sessionId] = info;
		}
	};

	SessionId[] getChunkObservers(ChunkWorldPos cwp) {
		if (auto observers = cwp in chunkObservers)
			return observers.clients;
		else
			return null;
	}

	void getDimensionObservers(Buffer!SessionId* sink, DimensionId dim)
	{
		foreach(pair; viewInfos.byKeyValue)
		{
			if (pair.value.viewBox.dimension == dim)
				sink.put(pair.key);
		}
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

	void removeObserver(SessionId sessionId) {
		if (sessionId in viewInfos) {
			changeObserverBox(sessionId, ChunkWorldPos.init, 0);
			viewInfos.remove(sessionId);
		}
		else
			warningf("removing observer %s, that was not added", sessionId);
	}

	WorldBox getObserverBox(SessionId sessionId) {
		ViewInfo info = viewInfos.get(sessionId, ViewInfo.init);
		return info.viewBox;
	}

	void changeObserverBox(SessionId sessionId, ChunkWorldPos observerPosition, int viewRadius) {
		WorldBox newBox = calcBox(observerPosition, viewRadius);
		changeObserverBox(sessionId, newBox);
	}

	void changeObserverBox(SessionId sessionId, WorldBox newBox) {
		ViewInfo info = viewInfos.get(sessionId, ViewInfo.init);
		WorldBox oldBox = info.viewBox;

		if (newBox == oldBox)
			return;

		info = ViewInfo(newBox);//, observerPosition, viewRadius);

		//infof("oldV %s newV %s", oldBox, newBox);
		TrisectResult tsect = trisect4d(oldBox, newBox);

		// remove observer
		foreach(a; tsect.aPositions) {
			removeChunkObserver(ChunkWorldPos(a, oldBox.dimension), sessionId);
			//infof("Rem %s", a);
		}

		// add observer
		foreach(b; tsect.bPositions) {
			addChunkObserver(ChunkWorldPos(b, newBox.dimension), sessionId);
		}

		if (newBox.empty)
			viewInfos.remove(sessionId);
		else
			viewInfos[sessionId] = info;
	}

	private bool addChunkObserver(ChunkWorldPos cwp, SessionId sessionId) {
		auto list = chunkObservers.get(cwp, ChunkObservers.init);
		if (list.add(sessionId)) {
			changeChunkNumObservers(cwp, list.numObservers);
			chunkObserverAdded(cwp, sessionId);
			chunkObservers[cwp] = list;
			return true;
		}
		return false;
	}

	private void removeChunkObserver(ChunkWorldPos cwp, SessionId sessionId) {
		auto list = chunkObservers.get(cwp, ChunkObservers.init);
		bool removed = list.remove(sessionId);
		if (removed)
			changeChunkNumObservers(cwp, list.numObservers);
		if (list.empty)
			chunkObservers.remove(cwp);
		else
			chunkObservers[cwp] = list;
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
