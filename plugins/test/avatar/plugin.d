module test.avatar.plugin;

import voxelman.log;
import voxelman.container.buffer;
import dlib.math;
import datadriven;
import netlib;
import pluginlib;
import std.math : sin, pow;

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
	double velocity = 0;
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

struct AvatarArmature
{
	Armature armature;

	Armature.Bone* body_, head, armUL, armUR, legUL, legUR, armLL, armLR, legLL, legLR;

	/// Resets arms & legs
	/// Params:
	///   strength = how strong this animation should be, like walk speed (should be 0-1)
	///   time = where in the animation we are (should cycle on whole values)
	void walkAnimation(float strength, float time)
	{
		armUL.reset();
		armUR.reset();
		legUL.reset();
		legUR.reset();
		armLL.reset();
		armLR.reset();
		legLL.reset();
		legLR.reset();
		enum armFlail = 2.0f;
		float rot = cast(float)(sin(time * 6.282) * armFlail);
		float rotOff = cast(float)(sin(time * 6.282 + 3.141) * armFlail);
		armUL.rotate(vec3(rot * strength, 0, 0));
		armUR.rotate(vec3(-rot * strength, 0, 0));
		armLL.rotate(vec3(-(rotOff + armFlail) * 0.25f * strength, 0, 0));
		armLR.rotate(vec3(-(rot + armFlail) * 0.25f * strength, 0, 0));
		legUL.rotate(vec3(-rot * strength, 0, 0));
		legUR.rotate(vec3(rot * strength, 0, 0));
		legLL.rotate(vec3(-(rotOff - armFlail) * 0.5f * strength, 0, 0));
		legLR.rotate(vec3(-(rot - armFlail) * 0.5f * strength, 0, 0));
	}

	/// Updates body & arms
	/// Params:
	///   time = where in the animation we are (should cycle on whole values)
	void addBreathing(float time)
	{
		float rot1 = cast(float)(sin(time * 6.282) * 0.0001f);
		float rot2 = cast(float)(sin(time * 6.282 * 2) * 0.0001f);
		body_.rotate(vec3(-rot1, 0, 0));
		armUL.rotate(vec3(-rot2, 0, -rot1));
		armUR.rotate(vec3(rot2, 0, rot1));
		armLL.rotate(vec3(-rot2, 0, -rot1) + 0.0001f);
		armLR.rotate(vec3(rot2, 0, rot1) + 0.0001f);
	}

	static AvatarArmature createDefault()
	{
		enum legOffset = -1.7f; // TODO: make position feet position instead

		AvatarArmature ret;
		ret.armature = Armature("avatar", translationMatrix(vec3(0, legOffset + 24 / 32.0, 0)));
		ret.armature.addRoot("body", Batch.cube32(vec3(8, 12, 4), Colors.blue,
				true, vec3(0, 12, 0)), Matrix4f.identity);
		ret.armature.addChild("body", "head", Batch.cube32(vec3(8, 8, 8),
				Colors.white, true, vec3(0, 8, 0)), translationMatrix(vec3(0, 24 / 32.0f, 0)));
		ret.armature.addChild("body", "armUL", Batch.cube32(vec3(4, 6, 4),
				Colors.brown, true, vec3(0, -2, 0)), translationMatrix(vec3(-12 / 32.0f, 20 / 32.0f, 0)));
		ret.armature.addChild("body", "armUR", Batch.cube32(vec3(4, 6, 4),
				Colors.cyan, true, vec3(0, -2, 0)), translationMatrix(vec3(12 / 32.0f, 20 / 32.0f, 0)));
		ret.armature.addChild("armUL", "armLL", Batch.cube32(vec3(4, 6, 4),
				Colors.brown, true, vec3(0, -6, 0)), translationMatrix(vec3(0, -8 / 32.0f, 0)));
		ret.armature.addChild("armUR", "armLR", Batch.cube32(vec3(4, 6, 4),
				Colors.cyan, true, vec3(0, -6, 0)), translationMatrix(vec3(0, -8 / 32.0f, 0)));
		ret.armature.addRoot("legUL", Batch.cube32(vec3(4, 6, 4), Colors.red, true,
				vec3(0, -6, 0)), translationMatrix(vec3(-4 / 32.0f, 0, 0)));
		ret.armature.addRoot("legUR", Batch.cube32(vec3(4, 6, 4), Colors.orangeRed,
				true, vec3(0, -6, 0)), translationMatrix(vec3(4 / 32.0f, 0, 0)));
		ret.armature.addChild("legUL", "legLL", Batch.cube32(vec3(4, 6, 4),
				Colors.red, true, vec3(0, -6, 0)), translationMatrix(vec3(0, -12 / 32.0f, 0)));
		ret.armature.addChild("legUR", "legLR", Batch.cube32(vec3(4, 6, 4),
				Colors.orangeRed, true, vec3(0, -6, 0)), translationMatrix(vec3(0, -12 / 32.0f, 0)));

		ret.body_ = ret.armature.findBoneByName("body");
		ret.head = ret.armature.findBoneByName("head");
		ret.armUL = ret.armature.findBoneByName("armUL");
		ret.armUR = ret.armature.findBoneByName("armUR");
		ret.armLL = ret.armature.findBoneByName("armLL");
		ret.armLR = ret.armature.findBoneByName("armLR");
		ret.legUL = ret.armature.findBoneByName("legUL");
		ret.legUR = ret.armature.findBoneByName("legUR");
		ret.legLL = ret.armature.findBoneByName("legLL");
		ret.legLR = ret.armature.findBoneByName("legLR");
		return ret;
	}
}

final class AvatarClient : IPlugin
{
	// IPlugin stuff
	mixin IdAndSemverFrom!"test.avatar.plugininfo";
	mixin AvatarPluginCommon;

	AvatarArmature playerArmature;
	EventDispatcherPlugin evDispatcher;
	GraphicsPlugin graphics;
	ClientSession session;
	ClientWorld clientWorld;
	float animationTime = 0;

	override void init(IPluginManager pluginman)
	{
		clientWorld = pluginman.getPlugin!ClientWorld;
		session = pluginman.getPlugin!ClientSession;
		graphics = pluginman.getPlugin!GraphicsPlugin;
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&updateSmoothPositions);
		evDispatcher.subscribeToEvent(&drawEntities);

		playerArmature = AvatarArmature.createDefault;
	}

	/// Updates SmoothedAvatarPosition components of entities containing AvatarPosition
	/// Makes network updates down to 16 fps look fluid on any framerate, but introduces 1/16s of delay
	void updateSmoothPositions(ref UpdateEvent event)
	{
		animationTime += event.deltaTime * 0.1f;
		while (animationTime >= 1)
			animationTime -= 1;
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
				float targetDistSq = (smooth.endDimPos.pos.xz - smooth.dimPos.pos.xz).lengthsqr;
				float targetVelocity = targetDistSq < 0.00001f ? 0 : targetDistSq < 0.1f ? 0.5f : 1;
				eman.set(row.id, *smooth);
				if (smooth.timeLeft > 0)
					smooth.timeLeft -= event.deltaTime;
				if (smooth.timeLeft < 0)
					smooth.timeLeft = 0;
				smooth.velocity = (smooth.velocity - targetVelocity) * pow(0.005,
						event.deltaTime) + targetVelocity;
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
				playerArmature.armature.root.reset();
				playerArmature.armature.root.rotate(vec3(0, (-p.heading.x).degtorad, 0));
				playerArmature.head.reset();
				playerArmature.head.rotate(vec3(-p.heading.y.degtorad, 0, 0));
				playerArmature.walkAnimation(row.smoothedAvatarPosition_0.velocity, animationTime * 15);
				playerArmature.addBreathing(animationTime * 5);
				graphics.draw(playerArmature.armature, translationMatrix(p.pos));
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
