/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.server.events;

import netlib.connection : ClientId;
import tharsis.prof : Profiler;

struct CommandEvent {
	ClientId clientId;
	string command;
	Profiler profiler;
	bool continuePropagation = true;
}

struct ClientConnectedEvent {
	ClientId clientId;
	Profiler profiler;
	bool continuePropagation = true;
}

struct ClientDisconnectedEvent {
	ClientId clientId;
	Profiler profiler;
	bool continuePropagation = true;
}

struct ClientLoggedInEvent {
	ClientId clientId;
	Profiler profiler;
	bool continuePropagation = true;
}
