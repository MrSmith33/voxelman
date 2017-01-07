/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.entity.plugin;

import voxelman.log;
import std.array : empty;

import cbor;
import pluginlib;
import datadriven;
import voxelman.container.buffer;
import voxelman.core.events;

import voxelman.eventdispatcher.plugin;
import voxelman.net.plugin;
import voxelman.world.clientworld;
import voxelman.world.serverworld;
import voxelman.world.storage : IoManager, StringMap, IoKey, PluginDataLoader, PluginDataSaver, IoStorageType;

import voxelman.entity.entityobservermanager;


struct ProcessComponentsEvent {
	float deltaTime;
}

struct ComponentSyncPacket
{
	ubyte[] data;
}

struct ComponentSyncStartPacket {}
struct ComponentSyncEndPacket {}

/// Use EntityComponentRegistry to receive EntityManager pointer.
final class EntityComponentRegistry : IResourceManager
{
	EntityManager* eman;
	override string id() @property { return "voxelman.entity.componentregistry"; }
}

mixin template EntityPluginCommon()
{
	private EntityComponentRegistry componentRegistry;
	private EntityManager eman;
	private EntityObserverManager entityObserverManager;
	private EntityIdManager eidMan;

	override void registerResourceManagers(void delegate(IResourceManager) registerHandler)
	{
		componentRegistry = new EntityComponentRegistry();
		eman.eidMan = &eidMan;
		componentRegistry.eman = &eman;
		registerHandler(componentRegistry);
	}
}

immutable string componentMapKey = "voxelman.entity.componentmap";

final class EntityPluginClient : IPlugin
{
	mixin IdAndSemverFrom!"voxelman.entity.plugininfo";
	mixin EntityPluginCommon;

	private EventDispatcherPlugin evDispatcher;
	private NetClientPlugin connection;
	private ClientWorld clientWorld;

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onUpdateEvent);
		clientWorld = pluginman.getPlugin!ClientWorld;
		connection = pluginman.getPlugin!NetClientPlugin;
		connection.registerPacket!ComponentSyncStartPacket(&handleComponentSyncStartPacket);
		connection.registerPacket!ComponentSyncPacket(&handleComponentSyncPacket);
		connection.registerPacket!ComponentSyncEndPacket(&handleComponentSyncEndPacket);
	}

	private void onUpdateEvent(ref UpdateEvent event)
	{
		evDispatcher.postEvent(ProcessComponentsEvent(event.deltaTime));
	}

	private void handleComponentSyncStartPacket(ubyte[] packetData)
	{
		eman.removeSerializedComponents(IoStorageType.network);
	}

	private void handleComponentSyncPacket(ubyte[] packetData)
	{
		auto packet = unpackPacketNoDup!ComponentSyncPacket(packetData);

		NetworkLoader netLoader;
		netLoader.stringMap = &clientWorld.serverStrings;

		ubyte[] data = packet.data;
		while(!data.empty)
		{
			ubyte[4] _key = data[$-4..$];
			uint key = *cast(uint*)&_key;
			uint entrySize = *cast(uint*)(data[$-4-4..$-4].ptr);
			ubyte[] entry = data[$-4-4-entrySize..$-4-4];
			netLoader.ioKeyToData[key] = entry;
			data = data[0..$-4-4-entrySize];
		}

		enum bool clearComponents = false;
		eman.load(netLoader, clearComponents);
		netLoader.ioKeyToData.clear();
	}

	private void handleComponentSyncEndPacket(ubyte[] packetData)
	{

	}
}

final class EntityPluginServer : IPlugin
{
	mixin IdAndSemverFrom!"voxelman.entity.plugininfo";
	mixin EntityPluginCommon;

	EventDispatcherPlugin evDispatcher;
	NetServerPlugin connection;
	EntityObserverManager entityObserverManager;

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto ioman = resmanRegistry.getResourceManager!IoManager;
		ioman.registerWorldLoadSaveHandlers(&load, &save);
		entityObserverManager.netSaver.stringMap = ioman.getStringMap();
		entityObserverManager.eman = &eman;
	}

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onUpdateEvent);
		evDispatcher.subscribeToEvent(&onPostUpdateEvent);
		connection = pluginman.getPlugin!NetServerPlugin;
		connection.registerPacket!ComponentSyncStartPacket();
		connection.registerPacket!ComponentSyncPacket();
		connection.registerPacket!ComponentSyncEndPacket();

		entityObserverManager.connection = connection;
		auto world = pluginman.getPlugin!ServerWorld;
		entityObserverManager.chunkObserverManager = world.chunkObserverManager;
	}

	private void onUpdateEvent(ref UpdateEvent event)
	{
		evDispatcher.postEvent(ProcessComponentsEvent(event.deltaTime));
	}

	private void onPostUpdateEvent(ref PostUpdateEvent)
	{
		entityObserverManager.sendEntitiesToObservers();
	}

	private void load(ref PluginDataLoader loader)
	{
		eman.eidMan.load(loader);
		eman.load(loader);
	}

	private void save(ref PluginDataSaver saver)
	{
		eman.eidMan.save(saver);
		eman.save(saver);
	}
}

struct NetworkSaver
{
	StringMap* stringMap;
	package Buffer!ubyte buffer;
	package size_t prevDataLength;

	IoStorageType storageType() { return IoStorageType.network; }

	Buffer!ubyte* beginWrite() {
		prevDataLength = buffer.data.length;
		return &buffer;
	}

	void endWrite(ref IoKey key) {
		uint entrySize = cast(uint)(buffer.data.length - prevDataLength);
		// dont write empty entries, since loader will return empty array for non-existing entries
		if (entrySize == 0) return;
		buffer.put(*cast(ubyte[4]*)&entrySize);
		uint int_key = stringMap.get(key);
		buffer.put(*cast(ubyte[4]*)&int_key);
	}

	void reset() { buffer.clear(); }

	ubyte[] data() { return buffer.data; }
}

struct NetworkLoader
{
	StringMap* stringMap;
	ubyte[][uint] ioKeyToData;

	IoStorageType storageType() { return IoStorageType.network; }

	ubyte[] readEntryRaw(ref IoKey key) {
		uint intKey = stringMap.get(key);
		auto data = ioKeyToData.get(intKey, null);
		return data;
	}
}
