/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module test.entitytest.plugin;

import std.experimental.logger;
import dlib.math;

import pluginlib;
import datadriven.api;
import datadriven.storage;
import voxelman.core.events;

import voxelman.entity.plugin;
import voxelman.eventdispatcher.plugin;
import voxelman.net.plugin;
import voxelman.worldinteraction.plugin;
import voxelman.input.keybindingmanager;

shared static this()
{
	pluginRegistry.regClientPlugin(new EntityTestPlugin!true);
	pluginRegistry.regServerPlugin(new EntityTestPlugin!false);
}

final class EntityTestPlugin(bool clientSide) : IPlugin
{
	// IPlugin stuff
	mixin IdAndSemverFrom!(test.entitytest.plugininfo);

	HashmapComponentStorage!Transform transformStorage;

	static if (clientSide)
		mixin EntityTestPluginClient;
	else
		mixin EntityTestPluginServer;
}

mixin template EntityTestPluginClient()
{
	import voxelman.graphics.plugin;

	Batch batch;
	EntityPluginClient entityPlugin;
	EventDispatcherPlugin evDispatcher;
	GraphicsPlugin graphics;
	WorldInteractionPlugin worldInteraction;
	NetClientPlugin connection;

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto keyBindingsMan = resmanRegistry.getResourceManager!KeyBindingManager;
		keyBindingsMan.registerKeyBinding(new KeyBinding(PointerButton.PB_1, "key.mainAction", null, &onMainActionRelease));
	}

	override void init(IPluginManager pluginman)
	{
		graphics = pluginman.getPlugin!GraphicsPlugin;
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&drawEntities);
		evDispatcher.subscribeToEvent(&process);
		worldInteraction = pluginman.getPlugin!WorldInteractionPlugin;
		entityPlugin = pluginman.getPlugin!EntityPluginClient;
		entityPlugin.registerComponent!Transform(&unpackTransform);
		connection = pluginman.getPlugin!NetClientPlugin;
		connection.registerPacket!EntityCreatePacket();
	}

	void onMainActionRelease(string key)
	{
		if (worldInteraction.cursorHit) {
			vec3 pos = vec3(worldInteraction.blockPos.vector + worldInteraction.hitNormal);
			infof("create entity at %s", pos);
			connection.send(EntityCreatePacket(pos));
		}
	}

	void unpackTransform(ubyte[] data)
	{
		entityPlugin.unpackComponents(transformStorage, data);
	}

	void process(ref ProcessComponentsEvent event)
	{
		batch.reset();
		auto query = componentQuery(transformStorage);
		foreach(row; query)
		{
			batch.putCube(row.transform.pos, vec3(1,1,1), Colors.black, true);
		}
	}

	void drawEntities(ref Render1Event event)
	{
		graphics.chunkShader.bind;
		graphics.draw(batch);
		graphics.chunkShader.unbind;
	}
}

mixin template EntityTestPluginServer()
{
	EntityPluginServer entityPlugin;
	EventDispatcherPlugin evDispatcher;
	NetServerPlugin connection;

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&process);
		evDispatcher.subscribeToEvent(&sync);
		entityPlugin = pluginman.getPlugin!EntityPluginServer;
		entityPlugin.registerComponent!Transform();
		connection = pluginman.getPlugin!NetServerPlugin;
		connection.registerPacket!EntityCreatePacket(&handleEntityCreatePacket);
	}

	void process(ref ProcessComponentsEvent event)
	{
		auto query = componentQuery(transformStorage);
		foreach(row; query)
		{
			row.transform.pos += vec3(0,1,0) * event.deltaTime;
		}
	}

	void sync(ref SyncComponentsEvent event)
	{
		entityPlugin.sendComponents(transformStorage);
	}

	void handleEntityCreatePacket(ubyte[] packetData, ClientId clientId)
	{
		auto packet = unpackPacket!EntityCreatePacket(packetData);

		EntityId eid = entityPlugin.entityManager.nextEntityId;
		transformStorage.add(eid, Transform(packet.pos));
		infof("Add %s %s", eid, packet.pos);
	}
}

struct Transform
{
	vec3 pos;
}

struct EntityCreatePacket
{
	vec3 pos;
}
