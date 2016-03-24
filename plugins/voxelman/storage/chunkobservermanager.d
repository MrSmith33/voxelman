/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.storage.chunkobservermanager;

import std.experimental.logger;
import dlib.math.vector : ivec3;
import netlib.connection : ClientId;
import voxelman.storage.coordinates : ChunkWorldPos;
import voxelman.storage.volume : Volume, TrisectResult, trisect, calcVolume;

enum chunkPackLoadSize = 200;

struct ViewInfo
{
	ClientId clientId;
	Volume viewVolume;
	//ivec3 viewRadius;
	ivec3 observerPosition;
	int viewRadius;

	size_t numObservedRings;
	size_t currentChunkIndex;
}

// Manages lists of observers per chunk
final class ChunkObserverManager {
	void delegate(ChunkWorldPos, size_t numObservers) changeChunkNumObservers;
	void delegate(ChunkWorldPos, ClientId) chunkObserverAdded;
	size_t delegate() loadQueueSpaceAvaliable;

	private ChunkObservers[ChunkWorldPos] chunkObservers;
	private ViewInfo[ClientId] viewInfos;

	void update() {

	}
	string a = q{

		import std.algorithm : sort;

		if (viewInfos.length == 0)
			return;

		size_t chunksToLoad = loadQueueSpaceAvaliable();
		//infof("queue space %s", chunksToLoad);

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
				if (currentRing > info.viewRadius)
					break;

				//infof("For infos C:%s VR:%s OR:%s CI:%s", info.clientId, info.viewRadius,
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
						//infof("Ring %s loaded for C:%s", info.numObservedRings, info.clientId);
						++info.numObservedRings;
						info.currentChunkIndex = 0;
						break;
					}
					popFront();

					bool added = addChunkObserver(ChunkWorldPos(position), info.clientId);

					if (added) {
						//infof("Add %s", position);
						--chunksToLoad;
						--chunksToLoadClient;
						++chunksObserved;

						if (chunksToLoad == 0)
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
			viewInfos[info.clientId] = info;
		}
	};

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

	void removeObserver(ClientId clientId) {
		if (clientId in viewInfos) {
			changeObserverVolume(clientId, ChunkWorldPos.init, 0);
			viewInfos.remove(clientId);
		}
		else
			warningf("removing observer %s, that was not added", clientId);
	}

	void changeObserverVolume(ClientId clientId, ChunkWorldPos observerPosition, int viewRadius) {
		ViewInfo info = viewInfos.get(clientId, ViewInfo.init);

		Volume oldVolume = info.viewVolume;
		immutable int size = viewRadius*2 + 1;
		Volume newVolume = calcVolume(observerPosition, viewRadius);

		if (newVolume == oldVolume)
			return;

		info = ViewInfo(clientId, newVolume, observerPosition.ivector, viewRadius);

		//infof("oldV %s newV %s", oldVolume, newVolume);
		TrisectResult tsect = trisect(oldVolume, newVolume);

		// remove observer
		foreach(a; tsect.aPositions) {
			removeChunkObserver(ChunkWorldPos(a), clientId);
			//infof("Rem %s", a);
		}

		// add observer
		foreach(b; tsect.bPositions) {
			addChunkObserver(ChunkWorldPos(b), clientId);
		}

		if (newVolume.empty)
			viewInfos.remove(clientId);
		else
			viewInfos[clientId] = info;
	}

	private bool addChunkObserver(ChunkWorldPos cwp, ClientId clientId) {
		auto list = chunkObservers.get(cwp, ChunkObservers.init);
		if (list.add(clientId)) {
			changeChunkNumObservers(cwp, list.numObservers);
			chunkObserverAdded(cwp, clientId);
			chunkObservers[cwp] = list;
			return true;
		}
		return false;
	}

	private void removeChunkObserver(ChunkWorldPos cwp, ClientId clientId) {
		auto list = chunkObservers.get(cwp, ChunkObservers.init);
		bool removed = list.remove(clientId);
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

	bool contains(ClientId clientId) const {
		import std.algorithm : canFind;
		return canFind(_clients, clientId);
	}

	bool add(ClientId clientId) {
		if (!contains(clientId)) {
			_clients ~= clientId;
			return true;
		} else
			return false;
	}

	bool remove(ClientId clientId) {
		import std.algorithm : remove, SwapStrategy;
		size_t startLength = _clients.length;
		_clients = remove!((a) => a == clientId, SwapStrategy.unstable)(_clients);
		return (startLength - _clients.length) > 0;
	}
}
