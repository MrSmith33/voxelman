/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.net.events;

import netlib : SessionId;
import datadriven : EntityId;

struct ClientConnectedEvent {
	SessionId sessionId;
}
struct ClientDisconnectedEvent {
	SessionId sessionId;
}
struct ThisClientConnectedEvent {}
struct ThisClientDisconnectedEvent {
	uint data;
}
struct ClientLoggedInEvent {
	EntityId clientId;
	bool newClient;
}
struct ClientLoggedOutEvent {
	EntityId clientId;
}
struct SendClientSettingsEvent {}
