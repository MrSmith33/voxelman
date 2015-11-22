/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.client.events;

import netlib.connection : ClientId;
import tharsis.prof : Profiler;

struct ClientLoggedInEvent {
	ClientId clientId;
	Profiler profiler;
	bool continuePropagation = true;
}
struct ClientLoggedOutEvent {
	ClientId clientId;
	Profiler profiler;
	bool continuePropagation = true;
}
struct ThisClientConnectedEvent {
	Profiler profiler;
	bool continuePropagation = true;
}
struct ThisClientDisconnectedEvent {
	Profiler profiler;
	bool continuePropagation = true;
}
struct ThisClientLoggedInEvent {
	ClientId myId;
	Profiler profiler;
	bool continuePropagation = true;
}
struct ChatMessageEvent {
	ClientId sender;
	string message;
	Profiler profiler;
	bool continuePropagation = true;
}
