module voxelman.servermain;

import voxelman.server.app;

void main(string[] args)
{
	auto app = new ServerApp;

	app.run(args);
}