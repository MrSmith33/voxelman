/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.server.events;

import netlib.connection : ClientId;
import voxelman.modules.eventdispatchermodule : GameEvent;

class CommandEvent : GameEvent
{
	this(ClientId clientId, string command) {
		this.clientId = clientId;
		this.command = command;
	}
	ClientId clientId;
	string command;
}

class ClientConnectedEvent : GameEvent
{
	this(ClientId clientId) {
		this.clientId = clientId;
	}
	ClientId clientId;
}

class ClientDisconnectedEvent : GameEvent
{
	this(ClientId clientId) {
		this.clientId = clientId;
	}
	ClientId clientId;
}

class ClientLoggedInEvent : GameEvent
{
	this(ClientId clientId) {
		this.clientId = clientId;
	}
	ClientId clientId;
}