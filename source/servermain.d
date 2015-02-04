module voxelman.servermain;

import voxelman.server.serverplugin;

void main(string[] args)
{
	auto serverPlugin = new ServerPlugin;

	serverPlugin.run(args);
}