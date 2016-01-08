/**
Copyright: Copyright (c) 2014-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module netlib.clientstorage;

import derelict.enet.enet : ENetPeer;
import netlib.connection : ClientId;


struct ClientStorage
{
	ENetPeer*[ClientId] clientPeers;
	// 0 is reserved for server.
	private ClientId _nextClientId = 1;

	ENetPeer* opIndex(ClientId id)
	{
		return clientPeers.get(id, null);
	}

	ClientId addClient(ENetPeer* peer)
	{
		ClientId id = nextPeerId;
		clientPeers[id] = peer;
		return id;
	}

	void removeClient(ClientId id)
	{
		clientPeers.remove(id);
	}

	size_t length()
	{
		return clientPeers.length;
	}

	private ClientId nextPeerId() @property
	{
		return _nextClientId++;
	}
}
