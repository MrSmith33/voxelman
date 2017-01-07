/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.session.sessionman;

import std.string : format;
import netlib : SessionId;
import datadriven : EntityId;

enum SessionType
{
	unknownClient, // client that is not yet logged in
	registeredClient // logged in client
}

struct Session
{
	SessionId sessionId;
	SessionType type;

	bool isLoggedIn() {
		return type == SessionType.registeredClient;
	}

	string name()
	{
		return isLoggedIn ? _name : format("%s", sessionId);
	}

	// used when type is registeredClient
	string _name;
	EntityId dbKey; // ditto
}

struct SessionManager
{
	Session*[SessionId] bySessionId;
	Session*[string] byClientName;

	void put(SessionId sessionId, SessionType type) {
		assert(sessionId !in bySessionId, "Session already exists");
		auto session = new Session(sessionId, type);
		bySessionId[session.sessionId] = session;
	}

	size_t length() {
		return bySessionId.length;
	}

	string sessionName(SessionId sessionId)
	{
		auto session = this[sessionId];
		return session ? session.name : format("%s", sessionId);
	}

	void identifySession(SessionId sessionId, string newName, EntityId clientId) {
		Session* session = bySessionId.get(sessionId, null);
		assert(session);

		if (session.name == newName) return;

		assert(session.name !in byClientName);
		byClientName.remove(session.name);
		if (newName) {
			byClientName[newName] = session;
		}
		session._name = newName;
		session.dbKey = clientId;
		session.type = SessionType.registeredClient;
	}

	Session* opIndex(string name) {
		return byClientName.get(name, null);
	}

	Session* opIndex(SessionId sessionId) {
		return bySessionId.get(sessionId, null);
	}

	void remove(SessionId sessionId) {
		auto session = bySessionId.get(sessionId, null);
		if (session) {
			if (session.type != SessionType.unknownClient)
				byClientName.remove(session.name);
			bySessionId.remove(sessionId);
		}
	}

	auto byValue() {
		return bySessionId.byValue;
	}
}
