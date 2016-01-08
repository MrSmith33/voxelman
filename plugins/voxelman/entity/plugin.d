/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.entity.plugin;

import std.experimental.logger;
import std.array : empty;

import cbor;
import pluginlib;
import datadriven.api;

import voxelman.eventdispatcher.plugin;
import voxelman.net.plugin;
import voxelman.core.events;

shared static this()
{
	pluginRegistry.regClientPlugin(new EntityPluginClient);
	pluginRegistry.regServerPlugin(new EntityPluginServer);
}

struct EntityManager
{
	private EntityId lastEntityId;

	EntityId nextEntityId()
	{
		return ++lastEntityId;
	}
}

struct ComponentInfo
{
	string name;
	ComponentUnpacker unpacker;
	TypeInfo componentType;
	size_t id;
}

struct ComponentSyncPacket
{
	size_t componentId;
	ubyte[] componentData;
}

struct ProcessComponentsEvent {
	float deltaTime;
	Profiler profiler;
	bool continuePropagation = true;
}

struct SyncComponentsEvent {
	Profiler profiler;
	bool continuePropagation = true;
}

final class EntityPluginClient : IPlugin
{
	mixin EntityPluginCommon;
	mixin EntityPluginClientImpl;
}

final class EntityPluginServer : IPlugin
{
	mixin EntityPluginCommon;
	mixin EntityPluginServerImpl;
}

alias ComponentUnpacker = void delegate(ubyte[] componentData);

mixin template EntityPluginCommon()
{
	mixin IdAndSemverFrom!(voxelman.entity.plugininfo);

	EventDispatcherPlugin evDispatcher;
	EntityManager entityManager;

	ComponentInfo*[] componentArray;
	ComponentInfo*[TypeInfo] componentMap;

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onUpdateEvent);
		evDispatcher.subscribeToEvent(&onPostUpdateEvent);
		connection = pluginman.getPlugin!(typeof(connection));
		connection.registerPacket!ComponentSyncPacket(&handleComponentSyncPacket);
	}

	void registerComponent(C)(ComponentUnpacker unpacker = null, string componentName = C.stringof)
	{
		size_t newId = componentArray.length;
		ComponentInfo* cinfo = new ComponentInfo(componentName, unpacker, typeid(C), newId);
		componentArray ~= cinfo;
		assert(typeid(C) !in componentMap);
		componentMap[typeid(C)] = cinfo;
	}

	void onUpdateEvent(ref UpdateEvent event)
	{
		evDispatcher.postEvent(ProcessComponentsEvent(event.deltaTime));
	}

	void onPostUpdateEvent(ref PostUpdateEvent event)
	{
		evDispatcher.postEvent(SyncComponentsEvent());
	}
}

mixin template EntityPluginClientImpl()
{
	NetClientPlugin connection;

	void unpackComponents(Storage)(ref Storage storage, ubyte[] data)
	{
		storage.removeAll();
		while(!data.empty)
		{
			storage.add(decodeCborSingle!size_t(data), decodeCborSingle!(componentType!Storage)(data));
		}
	}

	void handleComponentSyncPacket(ubyte[] packetData, ClientId clientId)
	{
		auto componentId = decodeCborSingle!size_t(packetData);

		if (componentId >= componentArray.length)
			return; // out of range

		auto unpacker = componentArray[componentId].unpacker;
		if (unpacker is null)
			return; // unpacker is not set

		unpacker(packetData);
	}
}

mixin template EntityPluginServerImpl()
{
	NetServerPlugin connection;

	void sendComponents(Storage)(Storage storage)
	{
		auto componentId = componentMap[typeid(componentType!Storage)].id;
		auto packetData = createComponentPacket(componentId, storage);
		if (packetData.length > 0)
			connection.sendToAll(packetData);
	}

	ubyte[] createComponentPacket(Storage)(size_t componentId, Storage storage)
	{
		ubyte[] bufferTemp = connection.buffer;
		size_t size;

		size = encodeCbor(bufferTemp[], connection.packetId!ComponentSyncPacket);
		size += encodeCbor(bufferTemp[size..$], componentId);

		foreach(pair; storage.byKeyValue())
		{
			size += encodeCbor(bufferTemp[size..$], pair.key);
			size += encodeCbor(bufferTemp[size..$], pair.value);
		}

		return bufferTemp[0..size];
	}

	void handleComponentSyncPacket(ubyte[] packetData, ClientId clientId)
	{
	}
}
