/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module netlib.clientstorage;

import derelict.enet.enet;
import netlib.connection;

// Needs at least peer field.
// struct Client
// {
//     ENetPeer* peer;
// }

struct ClientStorage(Client)
{
	import std.traits : hasMember;
	static assert(hasMember!(Client, "peer") &&
		is(typeof(Client.peer) == ENetPeer*),
		"Client type must have peer member");

	Client*[ClientId] clients;

	ClientId addClient(ENetPeer* peer)
	{
		ClientId id = nextPeerId;
		Client* client = new Client;
		client.peer = peer;
		clients[id] = client;
		return id;
	}

	Client* opIndex(ClientId id)
	{
		return clients.get(id, null);
	}

	void removeClient(ClientId id)
	{
		clients.remove(id);
	}

	ENetPeer* clientPeer(ClientId id)
	{
		return clients[id].peer;
	}

	size_t length()
	{
		return clients.length;
	}

	ClientId nextPeerId() @property
	{
		return _nextClientId++;
	}

	// 0 is reserved for server.
	private ClientId _nextClientId = 1;
}