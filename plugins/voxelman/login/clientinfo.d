/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.login.clientinfo;

import dlib.math.vector : vec3, vec2;

import voxelman.core.config;
import voxelman.world.storage.worldbox : WorldBox;
import voxelman.world.storage.coordinates;

enum SPAWN_DIMENSION = 0;

struct ClientInfo
{
	size_t id;
	string name;
	vec3 pos = START_POS;
	vec2 heading = vec2(-90, 0);
	DimensionId dimension;
	/// Used to reject wrong positions from client.
	/// Client sends positions updates with latest known key and server only accepts
	/// positions matching this key.
	/// After dimension change key is incremented.
	ubyte positionKey;

	int viewRadius = DEFAULT_VIEW_RADIUS;

	bool isLoggedIn;
	bool isSpawned;

	ChunkWorldPos chunk() {
		ChunkWorldPos cwp = BlockWorldPos(pos, dimension);
		return cwp;
	}
}
