module test.avatar.plugin;

import voxelman.log;
import voxelman.container.buffer;
import dlib.math;
import datadriven;
import netlib;
import pluginlib;

import voxelman.core.config;
import voxelman.core.events;
import voxelman.net.events;

import voxelman.entity.plugin;
import voxelman.eventdispatcher.plugin;
import voxelman.graphics.plugin;
import voxelman.session;
import voxelman.world.clientworld;
import voxelman.world.storage.coordinates : ClientDimPos;


@Component("avatar.AvatarPosition", Replication.toClient)
struct AvatarPosition
{
	ClientDimPos dimPos;
	DimensionId dimension;
}

mixin template AvatarPluginCommon()
{
	EntityManager* eman;

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto components = resmanRegistry.getResourceManager!EntityComponentRegistry;
		eman = components.eman;
		eman.registerComponent!AvatarPosition();
	}
}

final class AvatarClient : IPlugin
{
	// IPlugin stuff
	mixin IdAndSemverFrom!"test.avatar.plugininfo";
	mixin AvatarPluginCommon;

	Batch batch;
	EventDispatcherPlugin evDispatcher;
	GraphicsPlugin graphics;
	ClientSession session;
	ClientWorld clientWorld;

	override void init(IPluginManager pluginman)
	{
		clientWorld = pluginman.getPlugin!ClientWorld;
		session = pluginman.getPlugin!ClientSession;
		graphics = pluginman.getPlugin!GraphicsPlugin;
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&drawEntities);
	}

	void drawEntities(ref RenderSolid3dEvent event)
	{
		batch.reset();
		auto query = eman.query!AvatarPosition;
		foreach (row; query)
		{
			if (row.id != session.thisEntityId &&
				row.avatarPosition_0.dimension == clientWorld.currentDimension)
			{
				batch.putCube(row.avatarPosition_0.dimPos.pos, vec3(1,1,1), Colors.white, true);
			}
		}
		graphics.draw(batch);
	}
}

final class AvatarServer : IPlugin
{
	mixin IdAndSemverFrom!"test.avatar.plugininfo";
	mixin AvatarPluginCommon;

	EventDispatcherPlugin evDispatcher;
	ClientManager clientMan;

	override void init(IPluginManager pluginman)
	{
		clientMan = pluginman.getPlugin!ClientManager;
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onLogin);
		evDispatcher.subscribeToEvent(&onLogout);
		evDispatcher.subscribeToEvent(&onUpdateEvent);
	}

	void onLogin(ref ClientLoggedInEvent event) {
		eman.set(event.clientId, AvatarPosition());
	}

	void onLogout(ref ClientLoggedOutEvent event) {
		eman.remove!AvatarPosition(event.clientId);
	}

	void onUpdateEvent(ref UpdateEvent event)
	{
		auto query = eman.query!(ClientPosition, AvatarPosition);
		foreach (row; query)
		{
			row.avatarPosition_1.dimPos = row.clientPosition_0.dimPos;
			row.avatarPosition_1.dimension = row.clientPosition_0.dimension;
		}
	}
}
