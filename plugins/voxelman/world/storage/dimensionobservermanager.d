/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.dimensionobservermanager;

import voxelman.log;
import voxelman.container.buffer;
import voxelman.container.hash.map;
import voxelman.container.multihashset;
import netlib : SessionId;
import voxelman.core.config : DimensionId;

/// Stores a list of observers (i.e. players), per dimension
/// Can be used to notify players about some dimension local events,
/// or change of dimension's parameters (like borders)
struct DimensionObserverManager {
	void delegate(DimensionId, SessionId) dimensionObserverAdded;
	HashMap!(DimensionId, MultiHashSet!SessionId) dimObservers;
	// current observer dimension
	HashMap!(SessionId, DimensionId) observerDimensions;

	void updateObserver(SessionId sessionId, DimensionId dimensionId) {
		DimensionId* observerDim = sessionId in observerDimensions;
		if (observerDim is null)
		{
			observerDimensions[sessionId] = dimensionId;
			dimensionObserverAdded(dimensionId, sessionId);
			return;
		}

		if (dimensionId != (*observerDim))
		{
			if (auto oldObservers = (*observerDim) in dimObservers)
				oldObservers.remove(sessionId);
			auto observers = dimObservers.getOrCreate(dimensionId);
			if (observers.add(sessionId))
				dimensionObserverAdded(dimensionId, sessionId);
			(*observerDim) = dimensionId;
		}
	}

	void removeObserver(SessionId sessionId) {
		if (auto observerDim = sessionId in observerDimensions)
		{
			if (auto oldObservers = (*observerDim) in dimObservers)
			{
				oldObservers.remove(sessionId);
			}
			observerDimensions.remove(sessionId);
		}
	}

	// can use result in foreach
	auto getDimensionObservers(DimensionId dimensionId) {
		return dimObservers.get(dimensionId);
	}
}
