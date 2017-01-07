/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.clientworld;

import voxelman.log;
import netlib;
import pluginlib;
import voxelman.math;
import voxelman.geometry.cube;
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
import voxelman.gui.plugin : GuiPlugin;
import voxelman.graphics.plugin;
import voxelman.input.keybindingmanager;
import voxelman.session.client;
import voxelman.net.plugin : NetServerPlugin, NetClientPlugin;
import voxelman.dbg.plugin;

import voxelman.net.packets;
import voxelman.core.packets;

import voxelman.world.storage;
import voxelman.world.storage.dimensionobservermanager;
import voxelman.blockentity.blockentityaccess;

import voxelman.world.mesh.chunkmeshman;

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
	ClientSession session;
	BlockPluginClient blockPlugin;
	BlockEntityClient blockEntityPlugin;

	ConfigOption numWorkersOpt;
	Debugger dbg;

	size_t wastedClientLoads;

public:
	ChunkManager chunkManager;
	ChunkObserverManager chunkObserverManager;
	IdMapManagerClient idMapManager;
	WorldAccess worldAccess;
	BlockEntityAccess entityAccess;
	ChunkMeshMan chunkMeshMan;
	TimestampType currentTimestamp;
	HashSet!ChunkWorldPos chunksToRemesh;

	DimensionManager dimMan;

	// toggles/debug
	bool doUpdateObserverPosition = true;
	bool drawDebugMetadata;
	size_t totalLoadedChunks;

	// Observer data
	vec3 updatedCameraPos;
	ChunkWorldPos observerPosition;
	ubyte positionKey;
	SessionId observerSessionId;

	ConfigOption viewRadiusOpt;
	int viewRadius;

	// Send position interval
	double sendPositionTimer = 0;
	enum sendPositionInterval = 0.1;
	ChunkWorldPos prevChunkPos;

	StringMap serverStrings;

	mixin IdAndSemverFrom!"voxelman.world.plugininfo";

	override void registerResourceManagers(void delegate(IResourceManager) registerHandler) {}

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		ConfigManager config = resmanRegistry.getResourceManager!ConfigManager;
		numWorkersOpt = config.registerOption!int("num_workers", 4);
		viewRadiusOpt = config.registerOption!int("view_distance", DEFAULT_VIEW_RADIUS);

		KeyBindingManager keyBindingMan = resmanRegistry.getResourceManager!KeyBindingManager;
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_RIGHT_BRACKET, "key.incViewRadius", null, &onIncViewRadius));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_LEFT_BRACKET, "key.decViewRadius", null, &onDecViewRadius));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_U, "key.togglePosUpdate", null, &onTogglePositionUpdate));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_F2, "key.toggleMetaData", null, &onToggleMetaData));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_F5, "key.remesh", null, &onRemeshViewBox));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_F1, "key.chunkmeta", null, &onPrintChunkMeta));

		dbg = resmanRegistry.getResourceManager!Debugger;
	}

	// stubs
	private void handleLoadChunk(ChunkWorldPos) {}
	private void handleChunkObserverAdded(ChunkWorldPos, SessionId) {}

	override void preInit()
	{
		chunkManager = new ChunkManager();
		worldAccess = new WorldAccess(chunkManager);
		entityAccess = new BlockEntityAccess(chunkManager);

		ubyte numLayers = 2;
		chunkManager.setup(numLayers);
		chunkManager.loadChunkHandler = &handleLoadChunk;
		chunkManager.cancelLoadChunkHandler = &handleLoadChunk;
		chunkManager.isLoadCancelingEnabled = true;
		chunkManager.isChunkSavingEnabled = false;
		chunkManager.onChunkRemovedHandlers ~= &chunkMeshMan.onChunkRemoved;

		chunkMeshMan.getDimensionBorders = &dimMan.dimensionBorders;

		chunkObserverManager = new ChunkObserverManager();
		chunkObserverManager.changeChunkNumObservers = &chunkManager.setExternalChunkObservers;
		chunkObserverManager.chunkObserverAdded = &handleChunkObserverAdded;
		chunkObserverManager.loadQueueSpaceAvaliable = () => size_t.max;

		idMapManager.regIdMapHandler("string_map", &onServerStringMapReceived);
	}

	override void init(IPluginManager pluginman)
	{
		import std.algorithm.comparison : clamp;
		numWorkersOpt.set(clamp(numWorkersOpt.get!uint, 1, 16));

		viewRadius = viewRadiusOpt.get!uint;
		// duplicated code
		viewRadius = clamp(viewRadius, MIN_VIEW_RADIUS, MAX_VIEW_RADIUS);

		session = pluginman.getPlugin!ClientSession;

		auto gui = pluginman.getPlugin!GuiPlugin;

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

		worldAccess.blockInfos = blockPlugin.getBlocks();
	}

	WorldBox calcClampedBox(ChunkWorldPos cwp, int boxRadius)
	{
		int size = boxRadius*2 + 1;
		return WorldBox(cast(ivec3)(cwp.ivector3 - boxRadius),
			ivec3(size, size, size), cwp.w).intersection(dimMan.dimensionBorders(cwp.w));
	}

	private void handleIdMapPacket(ubyte[] packetData)
	{
		auto packet = unpackPacket!IdMapPacket(packetData);
		if (auto h = idMapManager.onMapReceivedHandlers.get(packet.mapName, null))
		{
			h(packet.names);
		}
	}

	private void onServerStringMapReceived(string[] strings)
	{
		serverStrings.load(strings);
	}

	private void onTogglePositionUpdate(string)
	{
		doUpdateObserverPosition = !doUpdateObserverPosition;
	}

	private void onToggleMetaData(string) {
		drawDebugMetadata = !drawDebugMetadata;
	}

	private void onRemeshViewBox(string) {
		WorldBox box = chunkObserverManager.getObserverBox(observerSessionId);
		remeshBox(box, true);
	}

	private void onPrintChunkMeta(string) {
		import voxelman.world.block : printChunkMetadata;
		auto cwp = observerPosition;
		auto snap = chunkManager.getChunkSnapshot(cwp, FIRST_LAYER);

		if (snap.isNull) {
			infof("No snapshot for %s", cwp);
			return;
		}
		printChunkMetadata(snap.metadata);
	}

	private void handlePreUpdateEvent(ref PreUpdateEvent event)
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

	private void drawDebugChunkInfo()
	{
		enum nearRadius = 2;
		ChunkWorldPos chunkPos = BlockWorldPos(graphics.camera.position, currentDimension);
		WorldBox nearBox = calcBox(chunkPos, nearRadius);

		drawDebugChunkMetadata(nearBox);
		drawDebugChunkGrid(nearBox);
	}

	private void drawDebugChunkMetadata(WorldBox box)
	{
		import voxelman.world.block;
		foreach(pos; box.positions)
		{
			vec3 blockPos = pos * CHUNK_SIZE;

			auto snap = chunkManager.getChunkSnapshot(
				ChunkWorldPos(pos, box.dimension), FIRST_LAYER);

			if (snap.isNull) continue;
			foreach(ubyte side; 0..6)
			{
				Solidity solidity = chunkSideSolidity(snap.metadata, cast(CubeSide)side);
				static Color4ub[3] colors = [Colors.white, Colors.gray, Colors.black];
				Color4ub color = colors[solidity];
				graphics.debugBatch.putCubeFace(blockPos + CHUNK_SIZE/2, vec3(2,2,2), cast(CubeSide)side, color, true);
			}

			if (snap.isUniform) {
				graphics.debugBatch.putCube(blockPos + CHUNK_SIZE/2-2, vec3(6,6,6), Colors.green, false);
			}
		}
	}

	private void drawDebugChunkGrid(WorldBox box)
	{
		vec3 gridPos = vec3(box.position*CHUNK_SIZE);
		ivec3 gridCount = box.size+1;
		vec3 gridOffset = vec3(CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE);
		graphics.debugBatch.put3dGrid(gridPos, gridCount, gridOffset, Colors.blue);
	}

	private void handlePostUpdateEvent(ref PostUpdateEvent event)
	{
		chunkManager.commitSnapshots(currentTimestamp);
		//chunkMeshMan.remeshChangedChunks(chunkManager.getModifiedChunks());
		chunkManager.clearModifiedChunks();
		chunkMeshMan.remeshChangedChunks(chunksToRemesh);
		chunksToRemesh.clear();

		if (doUpdateObserverPosition)
			sendPosition(event.deltaTime);

		dbg.setVar("wasted client loads", wastedClientLoads);
	}

	private void handleGameStopEvent(ref GameStopEvent gameStopEvent)
	{
		import core.thread;
		while(chunkMeshMan.numMeshChunkTasks > 0)
		{
			chunkMeshMan.update();
		}
		chunkMeshMan.stop();
	}

	private void handleSendClientSettingsEvent(ref SendClientSettingsEvent event)
	{
		connection.send(ViewRadiusPacket(viewRadius));
	}

	private void handleChunkDataPacket(ubyte[] packetData)
	{
		auto packet = unpackPacketNoDup!ChunkDataPacket(packetData);
		//tracef("Received %s ChunkDataPacket(%s,%s)", packetData.length,
		//	packet.chunkPos, packet.blockData.blocks.length);

		ChunkLayerItem[MAX_CHUNK_LAYERS] layers;
		auto cwp = ChunkWorldPos(packet.chunkPos);

		ubyte numChunkLayers;
		foreach(layer; packet.layers)
		{
			layers[numChunkLayers] = fromBlockData(layer);
			++numChunkLayers;
		}

		onChunkLoaded(cwp, layers[0..numChunkLayers]);
	}

	void onChunkLoaded(ChunkWorldPos cwp, ChunkLayerItem[] layers)
	{
		//tracef("onChunkLoaded %s added %s", cwp, chunkManager.isChunkAdded(cwp));
		++totalLoadedChunks;

		if (chunkManager.isChunkLoaded(cwp))
		{
			// TODO possible bug, copyLayer could be called when write buffer is not empty
			foreach(layer; layers)
			{
				WriteBuffer* writeBuffer = chunkManager.getOrCreateWriteBuffer(cwp, layer.layerId);
				copyLayer(layer, writeBuffer.layer);
			}
		}
		else if (chunkManager.isChunkAdded(cwp))
		{
			foreach(ref layer; layers)
			{
				if (!layer.isUniform)
				{
					ubyte[] data = allocLayerArray(layer.getArray!ubyte);
					layer.dataLength = cast(LayerDataLenType)data.length;
					layer.dataPtr = data.ptr;
				}
			}
			chunkManager.onSnapshotLoaded(cwp, layers, true);
		}
		else
		{
			// we received chunk data for unloaded chunk. Ignore it.
			++wastedClientLoads;
			return;
		}

		foreach(ChunkWorldPos pos; calcClampedBox(cwp, 1))
			chunksToRemesh.put(pos);
	}

	private void handleMultiblockChangePacket(ubyte[] packetData)
	{
		auto packet = unpackPacket!MultiblockChangePacket(packetData);
		auto cwp = ChunkWorldPos(packet.chunkPos);

		worldAccess.applyBlockChanges(cwp, packet.blockChanges);

		foreach(ChunkWorldPos pos; calcClampedBox(cwp, 1))
			chunksToRemesh.put(pos);
	}

	private void handleFillBlockBoxPacket(ubyte[] packetData)
	{
		auto packet = unpackPacketNoDup!FillBlockBoxPacket(packetData);

		worldAccess.fillBox(packet.box, packet.blockId);
		onBlockBoxChanged(packet.box);
	}

	void onBlockBoxChanged(WorldBox blockBox)
	{
		WorldBox observedBox = chunkObserverManager.getObserverBox(observerSessionId);
		WorldBox modifiedBox = calcModifiedMeshesBox(blockBox);
		WorldBox box = worldBoxIntersection(observedBox, modifiedBox);

		foreach(ChunkWorldPos pos; box)
			chunksToRemesh.put(pos);
	}

	private void handlePlaceBlockEntityPacket(ubyte[] packetData)
	{
		auto packet = unpackPacket!PlaceBlockEntityPacket(packetData);
		placeEntity(packet.box, packet.data,
			worldAccess, entityAccess);
		onBlockBoxChanged(packet.box);
	}

	private void handleRemoveBlockEntityPacket(ubyte[] packetData)
	{
		auto packet = unpackPacket!RemoveBlockEntityPacket(packetData);
		WorldBox changedBox = removeEntity(BlockWorldPos(packet.blockPos),
			blockEntityPlugin.blockEntityInfos, worldAccess, entityAccess, /*AIR*/1);
		onBlockBoxChanged(changedBox);
	}

	private void remeshBox(WorldBox box, bool printTime = false)
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
			remeshedChunks.put(ChunkWorldPos(pos, box.dimension));
		}
		if (printTime)
			chunkMeshMan.remeshChangedChunks(remeshedChunks, &onRemeshDone);
		else
			chunkMeshMan.remeshChangedChunks(remeshedChunks);
	}

	void sendPosition(double dt)
	{
		if (session.isSpawned)
		{
			sendPositionTimer += dt;
			if (sendPositionTimer > sendPositionInterval ||
				observerPosition != prevChunkPos)
			{
				connection.send(ClientPositionPacket(
					ClientDimPos(
						graphics.camera.position,
						graphics.camera.heading),
					observerPosition.w, positionKey));

				if (sendPositionTimer < sendPositionInterval)
					sendPositionTimer = 0;
				else
					sendPositionTimer -= sendPositionInterval;
			}
		}

		prevChunkPos = observerPosition;
	}

	void setDimensionBorders(DimensionId dim, Box borders)
	{
		DimensionInfo* dimInfo = dimMan.getOrCreate(dim);
		dimInfo.borders = borders;
		updateObserverPosition();
	}

	void setCurrentDimension(DimensionId dimension, ubyte positionKey) {
		observerPosition.w = dimension;
		this.positionKey = positionKey;
		updateObserverPosition();
	}

	bool isBlockSolid(ivec3 blockWorldPos) {
		auto block = worldAccess.getBlock(
			BlockWorldPos(blockWorldPos, observerPosition.w));
		return block != 0 && blockPlugin.getBlocks()[block].isVisible;
	}

	DimensionId currentDimension() @property {
		return observerPosition.w;
	}

	Box currentDimensionBorders() @property {
		return dimMan.dimensionBorders(observerPosition.dimension);
	}

	void incDimension() {
		string com = cast(string)makeFormattedText("dim %s", currentDimension() + 1);
		connection.send(CommandPacket(com));
	}
	void decDimension() {
		string com = cast(string)makeFormattedText("dim %s", currentDimension() - 1);
		connection.send(CommandPacket(com));
	}

	void updateObserverPosition() {
		if (session.isSpawned) {
			if (observerSessionId != session.thisSessionId) {
				chunkObserverManager.removeObserver(observerSessionId);
				observerSessionId = session.thisSessionId;
			}

			auto borders = dimMan.dimensionBorders(observerPosition.dimension);
			chunkObserverManager.changeObserverBox(
				observerSessionId, observerPosition, viewRadius, borders);
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
