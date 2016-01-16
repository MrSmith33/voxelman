/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.net.events;

import netlib.connection : ClientId;

struct ClientConnectedEvent {
	ClientId clientId;
}
struct ClientDisconnectedEvent {
	ClientId clientId;
}
struct ThisClientConnectedEvent {}
struct ThisClientDisconnectedEvent {
	uint data;
}
struct ClientLoggedInEvent {
	ClientId clientId;
}
struct ClientLoggedOutEvent {
	ClientId clientId;
}
struct SendClientSettingsEvent {}
