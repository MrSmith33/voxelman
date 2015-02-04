/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.client.events;

import netlib.connection : ClientId;
import voxelman.plugins.eventdispatcherplugin : GameEvent;

class ClientLoggedInEvent : GameEvent
{
	this(ClientId clientId) {
		this.clientId = clientId;
	}
	ClientId clientId;
}

class ClientLoggedOutEvent : GameEvent
{
	this(ClientId clientId) {
		this.clientId = clientId;
	}
	ClientId clientId;
}

class ThisClientConnectedEvent : GameEvent {}
class ThisClientDisconnectedEvent : GameEvent {}
class ThisClientLoggedInEvent : GameEvent
{
	this(ClientId myId) {
		this.myId = myId;
	}
	ClientId myId;
}

class ChatMessageEvent : GameEvent
{
	this(ClientId sender, string message) {
		this.sender = sender;
		this.message = message;
	}
	ClientId sender;
	string message;
}