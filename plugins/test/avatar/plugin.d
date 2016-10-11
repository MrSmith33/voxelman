module test.avatar.plugin;

import std.array;
import voxelman.log;
import dlib.math;

import netlib;
import pluginlib;
import voxelman.eventdispatcher.plugin;
import voxelman.net.plugin;
import voxelman.core.config;
import voxelman.core.events;
import voxelman.graphics.plugin;
import voxelman.session.client;
import voxelman.session.server;
import voxelman.world.clientworld;

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
	ClientSession session;
	ClientWorld clientWorld;

	override void init(IPluginManager pluginman)
	{
		clientWorld = pluginman.getPlugin!ClientWorld;
		session = pluginman.getPlugin!ClientSession;
		graphics = pluginman.getPlugin!GraphicsPlugin;
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&drawEntities);
		connection = pluginman.getPlugin!NetClientPlugin;
		connection.registerPacket!UpdateAvatarsPacket(&handleUpdateAvatarsPacket);
	}

	void drawEntities(ref RenderSolid3dEvent event)
	{
		graphics.draw(batch);
	}

	void handleUpdateAvatarsPacket(ubyte[] packetData, ClientId clientId)
	{
		auto packet = unpackPacket!UpdateAvatarsPacket(packetData);
		batch.reset();
		foreach (avatar; packet.avatars)
		{
			if (avatar.clientId != session.thisClientId && avatar.dimension == clientWorld.currentDimension)
			{
				batch.putCube(avatar.position, vec3(1,1,1), Colors.white, true);
			}
		}
	}
}

final class AvatarServer : IPlugin
{
	mixin IdAndSemverFrom!(test.avatar.plugininfo);

	EventDispatcherPlugin evDispatcher;
	NetServerPlugin connection;
	ClientManager clientMan;
	size_t lastAvatarsSent;

	override void init(IPluginManager pluginman)
	{
		clientMan = pluginman.getPlugin!ClientManager;
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onPostUpdateEvent);
		connection = pluginman.getPlugin!NetServerPlugin;
		connection.registerPacket!UpdateAvatarsPacket();
	}

	void onPostUpdateEvent(ref PostUpdateEvent event)
	{
		import std.algorithm : filter;
		Appender!(Avatar[]) avatars;
		avatars.reserve(clientMan.clients.length);
		foreach (cinfo; clientMan.clients.byValue.filter!(a=>a.isLoggedIn))
			avatars.put(Avatar(cinfo.id, cinfo.pos, cinfo.dimension, cinfo.heading));

		if (avatars.data.length < 2 && lastAvatarsSent < 2) return;

		connection.sendTo(clientMan.loggedInClients, UpdateAvatarsPacket(avatars.data));
		lastAvatarsSent = avatars.data.length;
	}
}

struct Avatar
{
	ClientId clientId;
	vec3 position;
	DimensionId dimension;
	vec2 heading;
}

struct UpdateAvatarsPacket
{
	Avatar[] avatars;
}
