/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.thread.servercontrol;

import core.atomic;

shared bool serverShouldStop;

bool isServerRunning()
{
	return !atomicLoad(serverShouldStop);
}

void stopServer()
{
	atomicStore(serverShouldStop, true);
}
