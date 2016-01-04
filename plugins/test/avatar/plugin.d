module test.avatar.plugin;

import std.array;
import std.experimental.logger;
import dlib.math;

import netlib;
import pluginlib;
import voxelman.eventdispatcher.plugin;
import voxelman.net.plugin;
import voxelman.core.events;
import voxelman.graphics.plugin;
import voxelman.client.plugin;
import voxelman.server.plugin;

shared static this()
{
	pluginRegistry.regClientPlugin(new AvatarClient);
	pluginRegistry.regServerPlugin(new AvatarServer);
}

final class AvatarClient : IPlugin
{
	// IPlugin stuff
	mixin IdAndSemverFrom!(test.avatar.plugininfo);

	Batch batch;
	EventDispatcherPlugin evDispatcher;
	GraphicsPlugin graphics;
	NetClientPlugin connection;
	ClientPlugin clientPlugin;

	override void init(IPluginManager pluginman)
	{
		clientPlugin = pluginman.getPlugin!ClientPlugin;
		graphics = pluginman.getPlugin!GraphicsPlugin;
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&drawEntities);
		connection = pluginman.getPlugin!NetClientPlugin;
		connection.registerPacket!UpdateAvatarsPacket(&handleUpdateAvatarsPacket);
	}

	void drawEntities(ref Render1Event event)
	{
		graphics.chunkShader.bind;
		graphics.draw(batch);
		graphics.chunkShader.unbind;
	}

	void handleUpdateAvatarsPacket(ubyte[] packetData, ClientId clientId)
	{
		auto packet = unpackPacket!UpdateAvatarsPacket(packetData);
		batch.reset();
		foreach (avatar; packet.avatars)
		if (avatar.clientId != clientPlugin.thisClientId)
		{
			batch.putCube(avatar.position, vec3(1,1,1), Colors.white, true);
		}
	}
}

final class AvatarServer : IPlugin
{
	mixin IdAndSemverFrom!(test.avatar.plugininfo);

	EventDispatcherPlugin evDispatcher;
	NetServerPlugin connection;
	ServerPlugin serverPlugin;

	override void init(IPluginManager pluginman)
	{
		serverPlugin = pluginman.getPlugin!ServerPlugin;
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onPostUpdateEvent);
		connection = pluginman.getPlugin!NetServerPlugin;
		connection.registerPacket!UpdateAvatarsPacket();
	}

	void onPostUpdateEvent(ref PostUpdateEvent event)
	{
		Appender!(Avatar[]) avatars;
		avatars.reserve(serverPlugin.clients.length);
		foreach (cinfo; serverPlugin.clients)
		if (cinfo.isLoggedIn)
		{
			avatars.put(Avatar(cinfo.id, cinfo.pos, cinfo.heading));
		}
		if (avatars.data.length < 2) return;

		connection.sendTo(serverPlugin.loggerInClients, UpdateAvatarsPacket(avatars.data));
	}
}

struct Avatar
{
	ClientId clientId;
	vec3 position;
	vec2 heading;
}

struct UpdateAvatarsPacket
{
	Avatar[] avatars;
}
