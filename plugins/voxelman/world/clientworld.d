/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.clientworld;

import std.experimental.logger;
import netlib;
import pluginlib;
import voxelman.math;
import voxelman.geometry.box;
import voxelman.utils.textformatter;

import voxelman.core.config;
import voxelman.core.events;
import voxelman.net.events;
import voxelman.utils.compression;
import voxelman.container.hashset;

import voxelman.block.plugin;
import voxelman.blockentity.plugin;
import voxelman.config.configmanager : ConfigOption, ConfigManager;
import voxelman.eventdispatcher.plugin : EventDispatcherPlugin;
import voxelman.graphics.plugin;
import voxelman.input.keybindingmanager;
import voxelman.login.plugin;
import voxelman.net.plugin : NetServerPlugin, NetClientPlugin;

import voxelman.net.packets;
import voxelman.core.packets;

import voxelman.world.storage.chunk;
import voxelman.world.storage.chunkmanager;
import voxelman.world.storage.chunkobservermanager;
import voxelman.world.storage.chunkprovider;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.worldbox;
import voxelman.world.storage.worldaccess;
import voxelman.blockentity.blockentityaccess;

import voxelman.client.chunkmeshman;

struct IdMapManagerClient
{
	void delegate(string[])[string] onMapReceivedHandlers;

	void regIdMapHandler(string mapName, void delegate(string[]) onMapReceived)
	{
		onMapReceivedHandlers[mapName] = onMapReceived;
	}
}


//version = DBG_COMPR;
final class ClientWorld : IPlugin
{
private:
	EventDispatcherPlugin evDispatcher;
	NetClientPlugin connection;
	GraphicsPlugin graphics;
	ClientDbClient clientDb;
	BlockPluginClient blockPlugin;
	BlockEntityClient blockEntityPlugin;

	ConfigOption numWorkersOpt;

public:
	ChunkManager chunkManager;
	ChunkObserverManager chunkObserverManager;
	IdMapManagerClient idMapManager;
	WorldAccess worldAccess;
	BlockEntityAccess entityAccess;
	ChunkMeshMan chunkMeshMan;
	TimestampType currentTimestamp;
	HashSet!ChunkWorldPos chunksToRemesh;

	// toggles/debug
	bool doUpdateObserverPosition = true;
	bool drawDebugMetadata;
	size_t totalLoadedChunks;

	// Observer data
	vec3 updatedCameraPos;
	ChunkWorldPos observerPosition;
	ubyte positionKey;
	ClientId observerClientId;

	ConfigOption viewRadiusOpt;
	int viewRadius;

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
		viewRadiusOpt = config.registerOption!uint("view_distance", DEFAULT_VIEW_RADIUS);

		KeyBindingManager keyBindingMan = resmanRegistry.getResourceManager!KeyBindingManager;
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_RIGHT_BRACKET, "key.incViewRadius", null, &onIncViewRadius));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_LEFT_BRACKET, "key.decViewRadius", null, &onDecViewRadius));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_U, "key.togglePosUpdate", null, &onTogglePositionUpdate));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_M, "key.toggleMetaData", null, &onToggleMetaData));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_F5, "key.remesh", null, &onRemeshViewBox));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_F1, "key.chunkmeta", null, &onPrintChunkMeta));
	}

	override void preInit()
	{
		chunkManager = new ChunkManager();
		worldAccess = new WorldAccess(chunkManager);
		entityAccess = new BlockEntityAccess(chunkManager);

		ubyte numLayers = 2;
		chunkManager.setup(numLayers);
		chunkManager.loadChunkHandler = &handleLoadChunk;
		chunkManager.isLoadCancelingEnabled = true;
		chunkManager.isChunkSavingEnabled = false;
		chunkManager.onChunkRemovedHandlers ~= &chunkMeshMan.onChunkRemoved;

		chunkObserverManager = new ChunkObserverManager();
		chunkObserverManager.changeChunkNumObservers = &chunkManager.setExternalChunkObservers;
		chunkObserverManager.chunkObserverAdded = &handleChunkObserverAdded;
		chunkObserverManager.loadQueueSpaceAvaliable = () => size_t.max;
	}

	override void init(IPluginManager pluginman)
	{
		viewRadius = viewRadiusOpt.get!uint;
		// duplicated code
		viewRadius = clamp(viewRadius, MIN_VIEW_RADIUS, MAX_VIEW_RADIUS);

		clientDb = pluginman.getPlugin!ClientDbClient;

		blockPlugin = pluginman.getPlugin!BlockPluginClient;
		blockEntityPlugin = pluginman.getPlugin!BlockEntityClient;
		chunkMeshMan.init(chunkManager, blockPlugin.getBlocks(),
			blockEntityPlugin.blockEntityInfos(), numWorkersOpt.get!uint);

		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&handlePreUpdateEvent);
		evDispatcher.subscribeToEvent(&handlePostUpdateEvent);
		evDispatcher.subscribeToEvent(&handleGameStopEvent);
		evDispatcher.subscribeToEvent(&handleSendClientSettingsEvent);

		connection = pluginman.getPlugin!NetClientPlugin;
		connection.registerPacketHandler!ChunkDataPacket(&handleChunkDataPacket);
		connection.registerPacketHandler!FillBlockBoxPacket(&handleFillBlockBoxPacket);
		connection.registerPacketHandler!MultiblockChangePacket(&handleMultiblockChangePacket);
		connection.registerPacketHandler!PlaceBlockEntityPacket(&handlePlaceBlockEntityPacket);
		connection.registerPacketHandler!RemoveBlockEntityPacket(&handleRemoveBlockEntityPacket);
		connection.registerPacketHandler!IdMapPacket(&handleIdMapPacket);

		graphics = pluginman.getPlugin!GraphicsPlugin;
	}

	override void postInit()
	{
		worldAccess.blockInfos = blockPlugin.getBlocks();
	}

	void handleIdMapPacket(ubyte[] packetData, ClientId clientId)
	{
		auto packet = unpackPacket!IdMapPacket(packetData);
		if (auto h = idMapManager.onMapReceivedHandlers.get(packet.mapName, null))
		{
			h(packet.names);
		}
	}

	void onTogglePositionUpdate(string)
	{
		doUpdateObserverPosition = !doUpdateObserverPosition;
	}

	void onToggleMetaData(string) {
		drawDebugMetadata = !drawDebugMetadata;
	}

	void onRemeshViewBox(string) {
		WorldBox box = chunkObserverManager.getObserverBox(observerClientId);
		remeshBox(box, true);
	}

	void onPrintChunkMeta(string) {
		import voxelman.block.utils : printChunkMetadata;
		auto cwp = observerPosition;
		auto snap = chunkManager.getChunkSnapshot(cwp, FIRST_LAYER);

		if (snap.isNull) {
			infof("No snapshot for %s", cwp);
			return;
		}
		printChunkMetadata(snap.metadata);
	}

	void handlePreUpdateEvent(ref PreUpdateEvent event)
	{
		++currentTimestamp;

		if (doUpdateObserverPosition)
		{
			observerPosition = ChunkWorldPos(
				BlockWorldPos(graphics.camera.position, observerPosition.w));
		}

		updateObserverPosition();
		chunkObserverManager.update();
		chunkMeshMan.update();

		if (drawDebugMetadata) {
			chunkMeshMan.drawDebug(graphics.debugBatch);
			drawDebugChunkInfo();
		}
	}

	void drawDebugChunkInfo()
	{
		enum nearRadius = 2;
		ChunkWorldPos chunkPos = BlockWorldPos(graphics.camera.position, currentDimention);
		WorldBox nearBox = calcBox(chunkPos, nearRadius);

		drawDebugChunkMetadata(nearBox);
		drawDebugChunkGrid(nearBox);
	}

	void drawDebugChunkMetadata(WorldBox box)
	{
		import voxelman.block.utils;
		foreach(pos; box.positions)
		{
			vec3 blockPos = pos * CHUNK_SIZE;

			auto snap = chunkManager.getChunkSnapshot(
				ChunkWorldPos(pos, box.dimention), FIRST_LAYER);

			if (snap.isNull) continue;
			foreach(ubyte side; 0..6)
			{
				Solidity solidity = chunkSideSolidity(snap.metadata, cast(Side)side);
				static Color3ub[3] colors = [Colors.white, Colors.gray, Colors.black];
				Color3ub color = colors[solidity];
				graphics.debugBatch.putCubeFace(blockPos + CHUNK_SIZE/2, vec3(2,2,2), cast(Side)side, color, true);
			}

			if (snap.isUniform) {
				graphics.debugBatch.putCube(blockPos + CHUNK_SIZE/2-2, vec3(6,6,6), Colors.green, false);
			}
		}
	}

	void drawDebugChunkGrid(WorldBox box)
	{
		vec3 gridPos = vec3(box.position*CHUNK_SIZE);
		ivec3 gridCount = box.size+1;
		vec3 gridOffset = vec3(CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE);
		graphics.debugBatch.put3dGrid(gridPos, gridCount, gridOffset, Colors.blue);
	}

	void handleChunkObserverAdded(ChunkWorldPos, ClientId) {}

	void handleLoadChunk(ChunkWorldPos) {}

	void handlePostUpdateEvent(ref PostUpdateEvent event)
	{
		chunkManager.commitSnapshots(currentTimestamp);
		//chunkMeshMan.remeshChangedChunks(chunkManager.getModifiedChunks());
		chunkManager.clearModifiedChunks();
		chunkMeshMan.remeshChangedChunks(chunksToRemesh);
		chunksToRemesh.clear();

		if (doUpdateObserverPosition)
			sendPosition(event.deltaTime);
	}

	void handleGameStopEvent(ref GameStopEvent gameStopEvent)
	{
		import core.thread;
		while(chunkMeshMan.numMeshChunkTasks > 0)
		{
			chunkMeshMan.update();
		}
		chunkMeshMan.stop();
	}

	void handleSendClientSettingsEvent(ref SendClientSettingsEvent event)
	{
		connection.send(ViewRadiusPacket(viewRadius));
	}

	void handleChunkDataPacket(ubyte[] packetData, ClientId peer)
	{
		auto packet = unpackPacketNoDup!ChunkDataPacket(packetData);
		//tracef("Received %s ChunkDataPacket(%s,%s)", packetData.length,
		//	packet.chunkPos, packet.blockData.blocks.length);

		ChunkLayerItem[8] layers;
		auto cwp = ChunkWorldPos(packet.chunkPos);

		ubyte numChunkLayers;
		foreach(layer; packet.layers)
		{
			if (!layer.uniform)
			{
				version(DBG_COMPR)infof("Receive %s %s\n(%(%02x%))", packet.chunkPos, layer.blocks.length, cast(ubyte[])layer.blocks);
				auto decompressed = decompressLayerData(layer.blocks);
				if (decompressed is null)
				{
					auto b = layer.blocks;
					infof("Fail %s %s\n(%(%02x%))", packet.chunkPos, b.length, cast(ubyte[])b);
					return;
				}
				else
				{
					layer.blocks = decompressed;
					layer.validate();
				}
			}
			layers[numChunkLayers] = fromBlockData(layer);
			++numChunkLayers;
		}

		onChunkLoaded(cwp, layers[0..numChunkLayers]);
	}

	void onChunkLoaded(ChunkWorldPos cwp, ChunkLayerItem[] layers)
	{
		//tracef("onChunkLoaded %s added %s", cwp, chunkManager.isChunkAdded(cwp));
		++totalLoadedChunks;
		static struct LoadedChunkData
		{
			ChunkWorldPos cwp;
			ChunkLayerItem[] layers;
			ChunkHeaderItem getHeader() { return ChunkHeaderItem(cwp, cast(uint)layers.length, 0); }
			ChunkLayerItem getLayer() {
				ChunkLayerItem layer = layers[0];
				layers = layers[1..$];
				return layer;
			}
		}


		if (chunkManager.isChunkLoaded(cwp))
		{
			foreach(layer; layers)
			{
				WriteBuffer* writeBuffer = chunkManager.getOrCreateWriteBuffer(cwp, layer.layerId);
				applyLayer(layer, writeBuffer.layer);
			}
		}
		else
		{
			chunkManager.onSnapshotLoaded(LoadedChunkData(cwp, layers), true);
		}

		chunksToRemesh.put(cwp);
		foreach(adj; adjacentPositions(cwp))
			chunksToRemesh.put(adj);
	}

	void handleMultiblockChangePacket(ubyte[] packetData, ClientId peer)
	{
		auto packet = unpackPacket!MultiblockChangePacket(packetData);
		auto cwp = ChunkWorldPos(packet.chunkPos);

		worldAccess.applyBlockChanges(cwp, packet.blockChanges);

		chunksToRemesh.put(cwp);
		foreach(adj; adjacentPositions(cwp))
			chunksToRemesh.put(adj);
	}

	void handleFillBlockBoxPacket(ubyte[] packetData, ClientId peer)
	{
		auto packet = unpackPacketNoDup!FillBlockBoxPacket(packetData);

		worldAccess.fillBox(packet.box, packet.blockId);
		onBlockBoxChanged(packet.box);
	}

	void onBlockBoxChanged(WorldBox blockBox)
	{
		WorldBox observedBox = chunkObserverManager.getObserverBox(observerClientId);
		WorldBox modifiedBox = calcModifiedMeshesBox(blockBox);
		WorldBox box = worldBoxIntersection(observedBox, modifiedBox);

		foreach(pos; box.positions)
			chunksToRemesh.put(ChunkWorldPos(pos, box.dimention));
	}

	void handlePlaceBlockEntityPacket(ubyte[] packetData, ClientId peer)
	{
		auto packet = unpackPacket!PlaceBlockEntityPacket(packetData);
		placeEntity(packet.box, packet.data,
			worldAccess, entityAccess);
		onBlockBoxChanged(packet.box);
	}

	void handleRemoveBlockEntityPacket(ubyte[] packetData, ClientId peer)
	{
		auto packet = unpackPacket!RemoveBlockEntityPacket(packetData);
		WorldBox changedBox = removeEntity(BlockWorldPos(packet.blockPos),
			blockEntityPlugin.blockEntityInfos, worldAccess, entityAccess, /*AIR*/1);
		onBlockBoxChanged(changedBox);
	}

	void remeshBox(WorldBox box, bool printTime = false)
	{
		import std.datetime : MonoTime, Duration, usecs, dur;
		MonoTime startTime = MonoTime.currTime;

		void onRemeshDone(size_t chunksRemeshed) {
			auto duration = MonoTime.currTime - startTime;
			int seconds; short msecs; short usecs;
			duration.split!("seconds", "msecs", "usecs")(seconds, msecs, usecs);
			infof("Remeshed %s chunks in % 3s.%03s,%03ss", chunksRemeshed, seconds, msecs, usecs);
		}

		HashSet!ChunkWorldPos remeshedChunks;
		foreach(pos; box.positions) {
			remeshedChunks.put(ChunkWorldPos(pos, box.dimention));
		}
		if (printTime)
			chunkMeshMan.remeshChangedChunks(remeshedChunks, &onRemeshDone);
		else
			chunkMeshMan.remeshChangedChunks(remeshedChunks);
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
					graphics.camera.position.arrayof,
					graphics.camera.heading.arrayof,
					observerPosition.w, positionKey));

				if (sendPositionTimer < sendPositionInterval)
					sendPositionTimer = 0;
				else
					sendPositionTimer -= sendPositionInterval;
			}
		}

		prevChunkPos = observerPosition;
	}

	void setCurrentDimention(DimentionId dimention, ubyte positionKey) {
		observerPosition.w = dimention;
		this.positionKey = positionKey;
		updateObserverPosition();
	}

	DimentionId currentDimention() @property {
		return observerPosition.w;
	}

	void incDimention() {
		string com = cast(string)makeFormattedText("dim %s", currentDimention() + 1);
		connection.send(CommandPacket(com));
	}
	void decDimention() {
		string com = cast(string)makeFormattedText("dim %s", currentDimention() - 1);
		connection.send(CommandPacket(com));
	}

	void updateObserverPosition() {
		if (clientDb.isSpawned) {
			if (observerClientId != clientDb.thisClientId) {
				chunkObserverManager.removeObserver(observerClientId);
				observerClientId = clientDb.thisClientId;
			}

			chunkObserverManager.changeObserverBox(observerClientId, observerPosition, viewRadius);
		}
	}

	void onIncViewRadius(string) {
		incViewRadius();
	}

	void onDecViewRadius(string) {
		decViewRadius();
	}

	void incViewRadius() {
		setViewRadius(getViewRadius() + 1);
	}

	void decViewRadius() {
		setViewRadius(getViewRadius() - 1);
	}

	int getViewRadius() {
		return viewRadius;
	}

	void setViewRadius(int newViewRadius) {
		auto oldViewRadius = viewRadius;
		// duplicated code
		viewRadius = clamp(newViewRadius, MIN_VIEW_RADIUS, MAX_VIEW_RADIUS);

		if (oldViewRadius != viewRadius)
		{
			connection.send(ViewRadiusPacket(viewRadius));
		}
	}
}
