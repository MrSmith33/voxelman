/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module test.entitytest.plugin;

import std.experimental.logger;
import dlib.math;
import std.array : Appender;

import pluginlib;
import datadriven.api;
import datadriven.storage;
import voxelman.core.events;
import voxelman.core.config : BlockType;
import voxelman.storage.coordinates : BlockWorldPos;
import derelict.imgui.imgui;
import voxelman.utils.textformatter;

import voxelman.entity.plugin;
import voxelman.eventdispatcher.plugin;
import voxelman.net.plugin;
import voxelman.worldinteraction.plugin;
import voxelman.world.plugin : ServerWorld;
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
		keyBindingsMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_E, "key.place_entity", null, &onMainActionRelease));
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
			ivec3 pos = worldInteraction.blockPos.vector + worldInteraction.hitNormal;
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
			batch.putCube(vec3(row.transform.pos), vec3(1,1,1), Color3ub(225, 169, 95), true);
		}
		igBegin("Debug");
		igTextf("Entities %s", transformStorage.length);
		igEnd();
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
	ServerWorld serverWorld;

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&process);
		evDispatcher.subscribeToEvent(&sync);
		entityPlugin = pluginman.getPlugin!EntityPluginServer;
		entityPlugin.registerComponent!Transform();
		connection = pluginman.getPlugin!NetServerPlugin;
		connection.registerPacket!EntityCreatePacket(&handleEntityCreatePacket);
		serverWorld = pluginman.getPlugin!ServerWorld;
	}

	void process(ref ProcessComponentsEvent event)
	{
		Appender!(EntityId[]) toRemove;
		auto wa = serverWorld.worldAccess;
		auto query = componentQuery(transformStorage);
		foreach(row; query)
		{
			ivec3 pos = row.transform.pos;
			if (wa.isFree(BlockWorldPos(pos+ivec3(0, -1, 0)))) // lower
				row.transform.pos += ivec3(0,-1,0);
			else if (wa.isFree(BlockWorldPos(pos+ivec3( 0, 0, -1))) && // side and lower
					wa.isFree(BlockWorldPos(pos+ivec3( 0, -1, -1))))
			{
				row.transform.pos = pos+ivec3( 0, 0, -1);
			}
			else if (wa.isFree(BlockWorldPos(pos+ivec3( 0, 0,  1))) && // side and lower
					wa.isFree(BlockWorldPos(pos+ivec3( 0, -1,  1))))
			{
				row.transform.pos = pos+ivec3( 0, 0,  1);
			}
			else if (wa.isFree(BlockWorldPos(pos+ivec3(-1, 0,  0))) && // side and lower
					wa.isFree(BlockWorldPos(pos+ivec3(-1, -1,  0))))
			{
				row.transform.pos = pos+ivec3(-1, 0,  0);
			}
			else if (wa.isFree(BlockWorldPos(pos+ivec3( 1, 0,  0))) && // side and lower
					wa.isFree(BlockWorldPos(pos+ivec3( 1, -1,  0))))
			{
				row.transform.pos = pos+ivec3( 1, 0,  0);
			}
			else // set sand
			{
				wa.setBlock(BlockWorldPos(pos), BlockType(5));
				toRemove.put(row.eid);
			}
		}
		foreach(eid; toRemove.data)
			transformStorage.remove(eid);
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
	}
}

struct Transform
{
	ivec3 pos;
}

struct EntityCreatePacket
{
	ivec3 pos;
}
