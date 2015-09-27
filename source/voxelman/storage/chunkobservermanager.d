/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.storage.chunkobservermanager;

import std.experimental.logger;
import netlib.connection : ClientId;
import voxelman.storage.coordinates : ChunkWorldPos;
import voxelman.storage.volume : Volume, TrisectResult, trisect;

// Manages lists of observers per chunk
final class ChunkObserverManager {
	void delegate(ChunkWorldPos, size_t numObservers) changeChunkNumObservers;
	void delegate(ChunkWorldPos, ClientId) chunkObserverAdded;

	private ChunkObservers[ChunkWorldPos] chunkObservers;
	private Volume[ClientId] viewVolumes;

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

	void addObserver(ClientId clientId, Volume volume) {
		assert(clientId !in viewVolumes, "Client is already added");
		changeObserverVolume(clientId, volume);
	}

	void removeObserver(ClientId clientId) {
		if (clientId in viewVolumes) {
			changeObserverVolume(clientId, Volume.init);
			viewVolumes.remove(clientId);
		}
		else
			warningf("removing observer %s, that was not added", clientId);
	}

	void changeObserverVolume(ClientId clientId, Volume newVolume) {
		Volume oldVolume = viewVolumes.get(clientId, Volume.init);
		viewVolumes[clientId] = newVolume;

		TrisectResult tsect = trisect(oldVolume, newVolume);

		// remove observer
		foreach(a; tsect.aPositions) {
			removeChunkObserver(ChunkWorldPos(a), clientId);
		}

		// add observer
		foreach(b; tsect.bPositions) {
			addChunkObserver(ChunkWorldPos(b), clientId);
		}
	}

	private void addChunkObserver(ChunkWorldPos cwp, ClientId clientId) {
		auto list = chunkObservers.get(cwp, ChunkObservers.init);
		list.add(clientId);
		changeChunkNumObservers(cwp, list.numObservers);
		chunkObserverAdded(cwp, clientId);
		chunkObservers[cwp] = list;
	}

	private void removeChunkObserver(ChunkWorldPos cwp, ClientId clientId) {
		auto list = chunkObservers.get(cwp, ChunkObservers.init);
		list.remove(clientId);
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

	void add(ClientId clientId) {
		_clients ~= clientId;
	}

	void remove(ClientId clientId) {
		import std.algorithm : remove, SwapStrategy;
		_clients = remove!((a) => a == clientId, SwapStrategy.unstable)(_clients);
	}
}
