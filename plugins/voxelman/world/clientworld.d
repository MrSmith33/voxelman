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

import voxelman.world.storage.chunk;
import voxelman.world.storage.chunkmanager;
import voxelman.world.storage.chunkobservermanager;
import voxelman.world.storage.chunkprovider;
import voxelman.world.storage.chunkstorage;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.volume;
import voxelman.world.storage.worldaccess;


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
	ChunkWorldPos observerPosition;
	bool drawDebugMetadata;

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
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_M, "key.toggleMetaData", null, &onToggleMetaData));
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
	}

	override void postInit()
	{
	}

	void onTogglePositionUpdate(string)
	{
		doUpdateObserverPosition = !doUpdateObserverPosition;
	}

	void onToggleMetaData(string) {
		drawDebugMetadata = !drawDebugMetadata;
	}

	void onPreUpdateEvent(ref PreUpdateEvent event)
	{
		if (doUpdateObserverPosition)
		{
			observerPosition = ChunkWorldPos(
				BlockWorldPos(graphics.camera.position, observerPosition.w));
		}
		updateObserverPosition();
		chunkMan.update();
		if (drawDebugMetadata) {
			chunkMan.chunkMeshMan.drawDebug(graphics.debugBatch);
			drawDebugChunkInfo();
		}
	}

	void drawDebugChunkInfo()
	{
		enum nearRadius = 2;
		ChunkWorldPos chunkPos = BlockWorldPos(graphics.camera.position, currentDimention);
		Volume nearVolume = calcVolume(chunkPos, nearRadius);

		drawDebugChunkMetadata(nearVolume);
		drawDebugChunkGrid(nearVolume);
		drawDebugChunkUniform(nearVolume);
	}

	void drawDebugChunkMetadata(Volume volume)
	{
		import voxelman.block.utils;
		foreach(pos; volume.positions)
		{
			vec3 blockPos = pos * CHUNK_SIZE;
			Chunk* chunk = chunkMan.chunkStorage.getChunk(ChunkWorldPos(pos, volume.dimention));
			if (chunk is null) continue;
			foreach(ubyte side; 0..6)
			{
				Solidity solidity = chunkSideSolidity(chunk.snapshot.blockData.metadata, cast(Side)side);
				static Color3ub[3] colors = [Colors.white, Colors.gray, Colors.black];
				Color3ub color = colors[solidity];
				graphics.debugBatch.putCubeFace(blockPos + CHUNK_SIZE/2, vec3(2,2,2), cast(Side)side, color, true);
			}
		}
	}

	void drawDebugChunkGrid(Volume volume)
	{
		vec3 gridPos = vec3(volume.position*CHUNK_SIZE);
		ivec3 gridCount = volume.size+1;
		vec3 gridOffset = vec3(CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE);
		graphics.debugBatch.put3dGrid(gridPos, gridCount, gridOffset, Colors.blue);
	}

	void drawDebugChunkUniform(Volume volume)
	{
		foreach(pos; volume.positions)
		{
			vec3 chunkBlockPos = pos * CHUNK_SIZE;
			graphics.debugBatch.putCube(chunkBlockPos + CHUNK_SIZE/2-2, vec3(6,6,6), Colors.green, false);
		}
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
		if (clientDb.isSpawned)
		{
			sendPositionTimer += dt;
			if (sendPositionTimer > sendPositionInterval ||
				observerPosition != prevChunkPos)
			{
				connection.send(ClientPositionPacket(
					graphics.camera.position,
					graphics.camera.heading,
					observerPosition.w));

				if (sendPositionTimer < sendPositionInterval)
					sendPositionTimer = 0;
				else
					sendPositionTimer -= sendPositionInterval;
			}
		}

		prevChunkPos = observerPosition;
	}

	void setCurrentDimention(DimentionId dimention)
	{
		observerPosition.w = dimention;
		updateObserverPosition();
	}

	DimentionId currentDimention() @property
	{
		return observerPosition.w;
	}

	void incDimention() { setCurrentDimention(cast(DimentionId)(currentDimention() + 1)); }
	void decDimention() { setCurrentDimention(cast(DimentionId)(currentDimention() - 1)); }

	void updateObserverPosition()
	{
		chunkMan.updateObserverPosition(observerPosition);
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
