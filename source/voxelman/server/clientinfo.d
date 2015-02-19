/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.server.clientinfo;

import netlib.connection : ENetPeer;
import dlib.math.vector : vec3, vec2;
import voxelman.chunk : ChunkRange;
import voxelman.config;

struct ClientInfo
{
	string name;
	vec3 pos = START_POS;
	vec2 heading = vec2(0, 0);
	int viewRadius = VIEW_RADIUS;
	ChunkRange visibleRegion;

	ENetPeer* peer;
	bool isLoggedIn;
}
