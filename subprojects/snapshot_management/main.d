/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module main;

import std.experimental.logger;
import voxelman.utils.log;
import server;

struct EditEvent {
	uint tick;
	int pos;
}

enum NUM_CLIENTS = 2;
enum NUM_TICKS = 10;
string[] clientNames = ["A", "B", "C", "D"];
EditEvent[] events = [
	{2, 0}, {3, 0}, {3, 1}, {4, -1}];

void main(string[] args)
{
	setupLogger("snapman.log");

	Server server;
	server.constructor();

	Client*[NUM_CLIENTS] clients;
	foreach(i, ref c; clients)
		c = new Client(clientNames[i]);
	clients[0].viewRadius = 1;

	// connect clients
	foreach(c; clients)
		server.onClientConnected(c);

	// main loop
	foreach(tick; 0..NUM_TICKS) {
		infof("-- %s", tick);
		server.preUpdate(clients[]);

		while (events.length > 0 && events[0].tick == tick) {
			server.setBlock(BlockWorldPos(events[0].pos * (CHUNK_SIZE)), 1);
			events = events[1..$];
		}

		server.postUpdate(clients[]);
	}

	// disconnect clients
	foreach(c; clients)
		server.onClientDisconnected(c);
}
