/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.clientmain;

import voxelman.utils.log;
import voxelman.client.app;
import anchovy.gui;

void main(string[] args)
{
	// BUG test
	//import dlib.geometry.frustum;
	//Frustum f;
	//Frustum f2;
	//f2 = f;

	setupLogger("client.log");
	auto app = new ClientApp(uvec2(1280, 720), "Voxel engine client test");
	app.run(args);
}
