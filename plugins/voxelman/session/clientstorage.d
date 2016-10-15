/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.session.clientstorage;

import voxelman.session.clientinfo;
import netlib : ClientId;

struct ClientStorage
{
	ClientInfo*[ClientId] clientsById;
	ClientInfo*[string] clientsByName;

	void put(ClientInfo* info) {
		assert(info);
		clientsById[info.id] = info;
	}

	size_t length() {
		return clientsById.length;
	}

	void setClientName(ClientInfo* info, string newName) {
		assert(info);
		assert(info.id in clientsById);

		if (info.name == newName) return;

		assert(info.name !in clientsByName);
		clientsByName.remove(info.name);
		if (newName) {
			clientsByName[newName] = info;
		}
		info.name = newName;
	}

	ClientInfo* opIndex(ClientId clientId) {
		return clientsById.get(clientId, null);
	}

	ClientInfo* opIndex(string name) {
		return clientsByName.get(name, null);
	}

	void remove(ClientId clientId) {
		auto info = clientsById.get(clientId, null);
		if (info) {
			clientsByName.remove(info.name);
		}
		clientsById.remove(clientId);
	}

	auto byValue() {
		return clientsById.byValue;
	}
}
