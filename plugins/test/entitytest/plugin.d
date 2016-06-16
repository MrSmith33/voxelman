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
import voxelman.core.config : BlockId;
import voxelman.world.storage.coordinates : BlockWorldPos;
import derelict.imgui.imgui;
import voxelman.utils.textformatter;

import voxelman.entity.plugin;
import voxelman.edit.plugin;
import voxelman.eventdispatcher.plugin;
import voxelman.net.plugin;
import voxelman.worldinteraction.plugin;
import voxelman.world.plugin;

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

		auto editPlugin = pluginman.getPlugin!EditPlugin;
		editPlugin.registerTool(
			new class ITool
			{
				this() { name = "test.entity.place_entity"; }
				override void onMainActionRelease() {
					placeEntity();
				}

				override void onUpdate() {
					if (!worldInteraction.cameraInSolidBlock)
					{
						worldInteraction.drawCursor(worldInteraction.sideBlockPos, Colors.green);
					}
				}
			}
		);
	}

	void placeEntity()
	{
		if (worldInteraction.cursorHit) {
			ivec4 pos = worldInteraction.sideBlockPos.vector;
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

	void drawEntities(ref RenderSolid3dEvent event)
	{
		graphics.chunkShader.bind;
		graphics.draw(batch);
		graphics.chunkShader.unbind;
	}
}

mixin template EntityTestPluginServer()
{
	immutable string transformKey = "test.entitytest.transform_component";
	EntityPluginServer entityPlugin;
	EventDispatcherPlugin evDispatcher;
	NetServerPlugin connection;
	ServerWorld serverWorld;

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto ioman = resmanRegistry.getResourceManager!IoManager;
		ioman.registerWorldLoadSaveHandlers(&read, &write);
	}

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
		bool isFree(ivec4 pos) {
			return wa.isFree(BlockWorldPos(pos));
		}
		bool isLoaded(ivec4 pos) {
			return wa.getBlock(BlockWorldPos(pos)) != 0;
		}
		foreach(row; query)
		{
			ivec4 pos = row.transform.pos;
			if (!isLoaded(pos) || !isLoaded(pos+ivec4(0, -1, 0, 0))) continue;
			if (isFree(pos+ivec4(0, -1, 0, 0))) // lower
				row.transform.pos += ivec4(0,-1,0, 0);
			else if (isFree(pos+ivec4( 0, 0, -1, 0)) && // side and lower
					isFree(pos+ivec4( 0, -1, -1, 0)))
			{
				row.transform.pos = pos+ivec4( 0, 0, -1, 0);
			}
			else if (isFree(pos+ivec4( 0, 0,  1, 0)) && // side and lower
					isFree(pos+ivec4( 0, -1,  1, 0)))
			{
				row.transform.pos = pos+ivec4( 0, 0,  1, 0);
			}
			else if (isFree(pos+ivec4(-1, 0,  0, 0)) && // side and lower
					isFree(pos+ivec4(-1, -1,  0, 0)))
			{
				row.transform.pos = pos+ivec4(-1, 0,  0, 0);
			}
			else if (isFree(pos+ivec4( 1, 0,  0, 0)) && // side and lower
					isFree(pos+ivec4( 1, -1,  0, 0)))
			{
				row.transform.pos = pos+ivec4( 1, 0,  0, 0);
			}
			else // set sand
			{
				wa.setBlock(BlockWorldPos(pos), BlockId(5));
				toRemove.put(row.eid);
			}
		}
		foreach(eid; toRemove.data) {
			transformStorage.remove(eid);
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
	}

	void read(ref PluginDataLoader loader)
	{
		ubyte[] data = loader.readEntry(transformKey);
		if (data.length) transformStorage.deserialize(data);
	}

	void write(ref PluginDataSaver saver)
	{
		auto sink = saver.tempBuffer;
		size_t size = transformStorage.serialize(sink);
		saver.writeEntry(transformKey, size);
	}
}

struct Transform
{
	ivec4 pos;
}

struct EntityCreatePacket
{
	ivec4 pos;
}
