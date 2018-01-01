/**
Copyright: Copyright (c) 2016-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.session.components;

import cbor : ignore;
import netlib : SessionId;
import datadriven;
import voxelman.math;
import voxelman.core.config;
import voxelman.world.storage;

void registerSessionComponents(EntityManager* eman)
{
	eman.registerComponent!ClientPosition();
	eman.registerComponent!LoggedInFlag();
	eman.registerComponent!SpawnedFlag();
	eman.registerComponent!ClientSettings();
	eman.registerComponent!ClientSessionInfo();
}

@Component("session.SpawnedFlag", Replication.none)
struct SpawnedFlag
{}

@Component("session.LoggedInFlag", Replication.none)
struct LoggedInFlag
{}

@Component("session.ClientPosition", Replication.toDb)
struct ClientPosition
{
	ClientDimPos dimPos;
	DimensionId dimension;

	/// Used to reject wrong positions from client.
	/// Client sends positions updates with latest known key and server only accepts
	/// positions matching this key.
	/// After dimension change key is incremented.
	@ignore ubyte positionKey;

	ChunkWorldPos chunk() {
		ChunkWorldPos cwp = BlockWorldPos(dimPos.pos, dimension);
		return cwp;
	}
}

@Component("session.ClientSettings", Replication.toDb)
struct ClientSettings
{
	int viewRadius = DEFAULT_VIEW_RADIUS;
}

@Component("session.ClientSessionInfo", Replication.none)
struct ClientSessionInfo
{
	string name;
	SessionId sessionId;
}
