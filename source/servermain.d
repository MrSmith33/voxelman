module voxelman.servermain;

import voxelman.server.servermodule;

void main(string[] args)
{
	auto serverModule = new ServerModule;

	serverModule.run(args);
}