/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.clientworld;

import std.experimental.logger;
import netlib;
import pluginlib;

import voxelman.core.config;
import voxelman.core.events;
import voxelman.net.events;
import voxelman.utils.compression;

import voxelman.input.keybindingmanager;
import voxelman.config.configmanager : ConfigOption, ConfigManager;
import voxelman.eventdispatcher.plugin : EventDispatcherPlugin;
import voxelman.net.plugin : NetServerPlugin, NetClientPlugin;
import voxelman.login.plugin;
import voxelman.block.plugin;

import voxelman.net.packets;
import voxelman.core.packets;

import voxelman.storage.chunk;
import voxelman.storage.chunkmanager;
import voxelman.storage.chunkobservermanager;
import voxelman.storage.chunkprovider;
import voxelman.storage.chunkstorage;
import voxelman.storage.coordinates;
import voxelman.storage.volume;
import voxelman.storage.worldaccess;


//version = DBG_COMPR;
final class ClientWorld : IPlugin
{
	import voxelman.graphics.plugin;
	import voxelman.world.chunkman;
private:
	EventDispatcherPlugin evDispatcher;
	NetClientPlugin connection;
	GraphicsPlugin graphics;
	ClientDbClient clientDb;

	ConfigOption numWorkersOpt;

public:
	ChunkMan chunkMan;
	WorldAccess worldAccess;

	bool doUpdateObserverPosition = true;
	vec3 updatedCameraPos;

	// Send position interval
	double sendPositionTimer = 0;
	enum sendPositionInterval = 0.1;
	ChunkWorldPos prevChunkPos;

	mixin IdAndSemverFrom!(voxelman.world.plugininfo);

	override void registerResourceManagers(void delegate(IResourceManager) registerHandler) {}

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		ConfigManager config = resmanRegistry.getResourceManager!ConfigManager;
		numWorkersOpt = config.registerOption!uint("num_workers", 4);

		KeyBindingManager keyBindingMan = resmanRegistry.getResourceManager!KeyBindingManager;
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_RIGHT_BRACKET, "key.incViewRadius", null, &onIncViewRadius));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_LEFT_BRACKET, "key.decViewRadius", null, &onDecViewRadius));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_U, "key.togglePosUpdate", null, &onTogglePositionUpdate));
	}

	override void preInit()
	{
		worldAccess.init(&chunkMan.chunkStorage.getChunk, () => 0);
		worldAccess.onChunkModifiedHandlers ~= &chunkMan.onChunkChanged;
	}

	override void init(IPluginManager pluginman)
	{
		clientDb = pluginman.getPlugin!ClientDbClient;

		auto blockPlugin = pluginman.getPlugin!BlockPluginClient;
		chunkMan.init(numWorkersOpt.get!uint, blockPlugin.getBlocks());

		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onPreUpdateEvent);
		evDispatcher.subscribeToEvent(&onPostUpdateEvent);
		evDispatcher.subscribeToEvent(&onGameStopEvent);
		evDispatcher.subscribeToEvent(&onSendClientSettingsEvent);

		connection = pluginman.getPlugin!NetClientPlugin;
		connection.registerPacketHandler!ChunkDataPacket(&handleChunkDataPacket);
		connection.registerPacketHandler!MultiblockChangePacket(&handleMultiblockChangePacket);

		graphics = pluginman.getPlugin!GraphicsPlugin;
		updatedCameraPos = graphics.camera.position;
	}

	override void postInit()
	{
		chunkMan.updateObserverPosition(graphics.camera.position);
	}

	void onTogglePositionUpdate(string)
	{
		doUpdateObserverPosition = !doUpdateObserverPosition;
	}

	void onPreUpdateEvent(ref PreUpdateEvent event)
	{
		if (doUpdateObserverPosition)
		{
			updatedCameraPos = graphics.camera.position;
		}
		chunkMan.updateObserverPosition(updatedCameraPos);
		chunkMan.update();
	}

	void onPostUpdateEvent(ref PostUpdateEvent event)
	{
		if (doUpdateObserverPosition)
			sendPosition(event.deltaTime);
	}

	void onGameStopEvent(ref GameStopEvent gameStopEvent)
	{
		import core.thread;
		chunkMan.stop();
		thread_joinAll();
	}

	void onSendClientSettingsEvent(ref SendClientSettingsEvent event)
	{
		connection.send(ViewRadiusPacket(chunkMan.viewRadius));
	}

	void handleChunkDataPacket(ubyte[] packetData, ClientId peer)
	{
		import cbor;
		auto packet = decodeCborSingle!ChunkDataPacket(packetData);
		//tracef("Received %s ChunkDataPacket(%s,%s)", packetData.length,
		//	packet.chunkPos, packet.blockData.blocks.length);
		if (!packet.blockData.uniform) {
			auto blocks = uninitializedArray!(BlockId[])(CHUNK_SIZE_CUBE);
			version(DBG_COMPR)infof("Receive %s %s\n(%(%02x%))", packet.chunkPos, packet.blockData.blocks.length, cast(ubyte[])packet.blockData.blocks);
			auto decompressed = decompress(packet.blockData.blocks, blocks);
			if (decompressed is null)
			{
				auto b = packet.blockData.blocks;
				infof("Fail %s %s\n(%(%02x%))", packet.chunkPos, b.length, cast(ubyte[])b);
				return;
			}
			else
			{
				packet.blockData.blocks = decompressed;
				packet.blockData.validate();
			}
		}

		chunkMan.onChunkLoaded(ChunkWorldPos(packet.chunkPos), packet.blockData);
	}

	void handleMultiblockChangePacket(ubyte[] packetData, ClientId peer)
	{
		auto packet = unpackPacket!MultiblockChangePacket(packetData);
		Chunk* chunk = chunkMan.chunkStorage.getChunk(ChunkWorldPos(packet.chunkPos));
		// We can receive data for chunk that is already deleted.
		if (chunk is null || chunk.isMarkedForDeletion)
			return;
		chunkMan.onChunkChanged(chunk, packet.blockChanges);
	}

	void sendPosition(double dt)
	{
		ChunkWorldPos chunkPos = BlockWorldPos(graphics.camera.position);

		if (clientDb.isSpawned)
		{
			sendPositionTimer += dt;
			if (sendPositionTimer > sendPositionInterval ||
				chunkPos != prevChunkPos)
			{
				connection.send(ClientPositionPacket(
					graphics.camera.position,
					graphics.camera.heading));

				if (sendPositionTimer < sendPositionInterval)
					sendPositionTimer = 0;
				else
					sendPositionTimer -= sendPositionInterval;
			}
		}

		prevChunkPos = chunkPos;
	}

	void onIncViewRadius(string)
	{
		incViewRadius();
	}

	void onDecViewRadius(string)
	{
		decViewRadius();
	}

	void incViewRadius()
	{
		setViewRadius(getViewRadius() + 1);
	}

	void decViewRadius()
	{
		setViewRadius(getViewRadius() - 1);
	}

	int getViewRadius()
	{
		return chunkMan.viewRadius;
	}

	void setViewRadius(int newViewRadius)
	{
		import std.algorithm : clamp;
		auto oldViewRadius = chunkMan.viewRadius;
		chunkMan.viewRadius = clamp(newViewRadius,
			MIN_VIEW_RADIUS, MAX_VIEW_RADIUS);

		if (oldViewRadius != chunkMan.viewRadius)
		{
			connection.send(ViewRadiusPacket(chunkMan.viewRadius));
		}
	}
}
