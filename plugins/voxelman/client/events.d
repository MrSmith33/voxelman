/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
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
struct ThisClientLoggedInEvent {
	ClientId thisClientId;
	Profiler profiler;
	bool continuePropagation = true;
}
struct ChatMessageEvent {
	ClientId sender;
	string message;
	Profiler profiler;
	bool continuePropagation = true;
}
