/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.server.clientinfo;

import netlib.connection : ENetPeer;

struct ClientInfo
{
	string name;
	ENetPeer* peer;
}