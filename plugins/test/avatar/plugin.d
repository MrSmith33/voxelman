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
import voxelman.world.storage.coordinates;

/// Represents the entity position shared between server & client which contains the entity position & dimension
@Component("avatar.AvatarPosition", Replication.toClient)
struct AvatarPosition
{
	ClientDimPos dimPos;
	DimensionId dimension;
}

/// Represents the client only position where the entity is currently effectively rendered for smoother gameplay
@Component("avatar.SmoothedAvatarPosition", Replication.none)
struct SmoothedAvatarPosition
{
	ClientDimPos startDimPos;
	ClientDimPos endDimPos;
	ClientDimPos dimPos;
	DimensionId dimension;
	double timeLeft = 0;
}

mixin template AvatarPluginCommon()
{
	EntityManager* eman;

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto components = resmanRegistry.getResourceManager!EntityComponentRegistry;
		eman = components.eman;
		eman.registerComponent!AvatarPosition();
		eman.registerComponent!SmoothedAvatarPosition();
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
		evDispatcher.subscribeToEvent(&updateSmoothPositions);
		evDispatcher.subscribeToEvent(&drawEntities);

		batch.reset();
		batch.putCube(vec3(-0.25f, -0.25f, -0.25f), vec3(0.5f, 0.5f, 0.5f), Colors.white, true);
	}

	/// Updates SmoothedAvatarPosition components of entities containing AvatarPosition
	/// Makes network updates down to 16 fps look fluid on any framerate, but introduces 1/16s of delay
	void updateSmoothPositions(ref UpdateEvent event)
	{
		// what time to expect between network updates
		enum UpdateTime = 1 / 16.0;
		auto query = eman.query!AvatarPosition;
		foreach (row; query)
		{
			if (row.id != session.thisEntityId)
			{
				auto raw = row.avatarPosition_0.dimPos;
				auto smooth = eman.getOrCreate(row.id, SmoothedAvatarPosition(raw, raw,
						raw, row.avatarPosition_0.dimension, 0));
				if ((smooth.endDimPos.pos - raw.pos).lengthsqr > 0.00001f
						|| (smooth.endDimPos.heading - raw.heading).lengthsqr > 0.00001f)
				{
					smooth.startDimPos = smooth.dimPos;
					smooth.endDimPos = raw;
					smooth.timeLeft = UpdateTime;
				}
				smooth.dimPos.pos = lerp(smooth.endDimPos.pos, smooth.startDimPos.pos,
						smooth.timeLeft / UpdateTime);
				smooth.dimPos.heading = lerp(smooth.endDimPos.heading,
						smooth.startDimPos.heading, smooth.timeLeft / UpdateTime);
				smooth.dimension = row.avatarPosition_0.dimension;
				eman.set(row.id, *smooth);
				if (smooth.timeLeft > 0)
					smooth.timeLeft -= event.deltaTime;
				if (smooth.timeLeft < 0)
					smooth.timeLeft = 0;
			}
		}
	}

	/// Takes the SmoothedAvatarPosition component off each entity and draws a cube
	void drawEntities(ref RenderSolid3dEvent event)
	{
		auto query = eman.query!SmoothedAvatarPosition;
		foreach (row; query)
		{
			if (row.id != session.thisEntityId
					&& row.smoothedAvatarPosition_0.dimension == clientWorld.currentDimension)
			{
				ClientDimPos p = row.smoothedAvatarPosition_0.dimPos;
				// TODO: add API for creating armatures/body groups & draw these instead of this cube
				graphics.draw(batch,
						translationMatrix(p.pos) * fromEuler(vec3(-p.heading.y.degtorad,
							(-p.heading.x).degtorad, 0)));
			}
		}
	}
}

final class AvatarServer : IPlugin
{
	mixin IdAndSemverFrom!"test.avatar.plugininfo";
	mixin AvatarPluginCommon;

	EventDispatcherPlugin evDispatcher;
	EntityPluginServer entityPlugin;

	override void init(IPluginManager pluginman)
	{
		entityPlugin = pluginman.getPlugin!EntityPluginServer;
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onLogin);
		evDispatcher.subscribeToEvent(&onLogout);
		evDispatcher.subscribeToEvent(&onMove);
	}

	void onLogin(ref ClientLoggedInEvent event)
	{
		eman.set(event.clientId, AvatarPosition());
		// required for incremental updates
		entityPlugin.entityObserverManager.addEntity(event.clientId, ChunkWorldPos(0));
	}

	void onLogout(ref ClientLoggedOutEvent event)
	{
		eman.remove!AvatarPosition(event.clientId);
		// required for incremental updates
		entityPlugin.entityObserverManager.removeEntity(event.clientId);
	}

	void onMove(ref ClientMovedEvent event)
	{
		eman.set(event.clientId, AvatarPosition(event.pos, event.dimension));
		// required for incremental updates
		entityPlugin.entityObserverManager.updateEntityPos(event.clientId,
				ChunkWorldPos(BlockWorldPos(event.pos.pos, event.dimension)));
	}
}
