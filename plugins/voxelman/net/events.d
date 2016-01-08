/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.net.events;

import netlib.connection : ClientId;
import tharsis.prof : Profiler;

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

struct ThisClientConnectedEvent {
	Profiler profiler;
	bool continuePropagation = true;
}

struct ThisClientDisconnectedEvent {
	uint data;
	Profiler profiler;
	bool continuePropagation = true;
}
