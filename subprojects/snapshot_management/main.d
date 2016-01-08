/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module main;

import std.experimental.logger;
import voxelman.utils.log;
import server;
import storage;

struct EditEvent {
	uint tick;
	int pos;
}

enum NUM_CLIENTS = 2;
enum NUM_TICKS = 20;
string[] clientNames = ["A", "B", "C", "D"];
EditEvent[] events = [
	{2, 0}, {3, 0}, {3, 1}, {4, -1}];

void main(string[] args)
{
	setupLogger("snapman.log");

	Server server = new Server();

	Client*[NUM_CLIENTS] clients;
	foreach(i, ref c; clients)
		c = new Client(clientNames[i], cast(uint)i+1, Volume1D(0, 1));
	clients[0].viewVolume = Volume1D(-1, 3);

	// connect clients
	foreach(c; clients)
		server.onClientConnected(c);

	// main loop
	foreach(tick; 0..NUM_TICKS) {
		infof("-- %s", tick);
		server.preUpdate();

		while (events.length > 0 && events[0].tick == tick) {
			server.setBlock(BlockWorldPos(events[0].pos * (CHUNK_SIZE)), 1);
			events = events[1..$];
		}

		if (tick == 10) {
			server.save();
		}

		server.postUpdate();
	}

	// disconnect clients
	foreach(c; clients)
		server.onClientDisconnected(c);
}
