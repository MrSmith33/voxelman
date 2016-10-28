/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
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

import voxelman.eventdispatcher.plugin;
import voxelman.net.plugin;
import voxelman.core.events;
import voxelman.world.clientworld;
import voxelman.world.serverworld;
import voxelman.world.storage : IoManager, StringMap, IoKey, PluginDataLoader, PluginDataSaver;

shared static this()
{
	pluginRegistry.regClientPlugin(new EntityPluginClient);
	pluginRegistry.regServerPlugin(new EntityPluginServer);
}

struct ProcessComponentsEvent {
	float deltaTime;
}

struct ComponentSyncPacket
{
	ubyte[] data;
}

struct ComponentIoKeyMapPacket
{
	ubyte[] data;
}

alias ComponentUnpacker = void delegate(ubyte[] componentData);

/// Use ComponentRegistry to receive EntityManager pointer.
final class ComponentRegistry : IResourceManager
{
	EntityManager* eman;
	override string id() @property { return "voxelman.entity.componentregistry"; }
}

mixin template EntityPluginCommon()
{
	private ComponentRegistry componentRegistry;
	private EntityManager* eman;

	override void registerResourceManagers(void delegate(IResourceManager) registerHandler)
	{
		componentRegistry = new ComponentRegistry();
		eman = new EntityManager;
		componentRegistry.eman = eman;
		registerHandler(componentRegistry);
	}
}

immutable string componentMapKey = "voxelman.entity.componentmap";

final class EntityPluginClient : IPlugin
{
	mixin IdAndSemverFrom!(voxelman.entity.plugininfo);
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
		connection.registerPacket!ComponentSyncPacket(&handleComponentSyncPacket);
	}

	private void onUpdateEvent(ref UpdateEvent event)
	{
		evDispatcher.postEvent(ProcessComponentsEvent(event.deltaTime));
	}

	private void handleComponentSyncPacket(ubyte[] packetData, ClientId clientId)
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

		eman.load(netLoader);
	}
}

final class EntityPluginServer : IPlugin
{
	mixin IdAndSemverFrom!(voxelman.entity.plugininfo);
	mixin EntityPluginCommon;

	EventDispatcherPlugin evDispatcher;
	NetServerPlugin connection;
	NetworkSaver netSaver;

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto ioman = resmanRegistry.getResourceManager!IoManager;
		ioman.registerWorldLoadSaveHandlers(&load, &save);
		netSaver.stringMap = ioman.getStringMap();
	}

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onUpdateEvent);
		evDispatcher.subscribeToEvent(&onPostUpdateEvent);
		connection = pluginman.getPlugin!NetServerPlugin;
		connection.registerPacket!ComponentSyncPacket();
	}

	private void onUpdateEvent(ref UpdateEvent event)
	{
		evDispatcher.postEvent(ProcessComponentsEvent(event.deltaTime));
	}

	private void onPostUpdateEvent(ref PostUpdateEvent)
	{
		eman.save(netSaver);
		connection.sendToAll(ComponentSyncPacket(netSaver.data));
		netSaver.reset();
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
	private Buffer!ubyte buffer;
	private size_t prevDataLength;

	Buffer!ubyte* beginWrite() {
		prevDataLength = buffer.data.length;
		return &buffer;
	}

	void endWrite(ref IoKey key) {
		uint entrySize = cast(uint)(buffer.data.length - prevDataLength);
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

	ubyte[] readEntryRaw(ref IoKey key) {
		uint intKey = stringMap.get(key);
		auto data = ioKeyToData.get(intKey, null);
		return data;
	}
}
