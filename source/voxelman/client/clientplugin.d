/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.client.clientplugin;

import core.thread : thread_joinAll;
import core.time;
import std.datetime : StopWatch;
import std.experimental.logger;

import anchovy.gui;
import anchovy.core.interfaces.iwindow;
import dlib.math.vector;
import dlib.math.matrix : Matrix4f;
import dlib.math.affine : translationMatrix;
import derelict.enet.enet;
import tharsis.prof;

import plugin;
import plugin.pluginmanager;
import resource;
import resource.resourcemanagerregistry;

import netlib.connection;
import netlib.baseclient;

import voxelman.plugins.eventdispatcherplugin;
import voxelman.plugins.graphicsplugin;
import voxelman.plugins.guiplugin;
import voxelman.plugins.inputplugin;
import voxelman.client.plugins.editplugin;
import voxelman.client.plugins.movementplugin;
import voxelman.client.plugins.worldinteractionplugin;
import voxelman.resourcemanagers.config;
import voxelman.resourcemanagers.keybindingmanager;

import voxelman.config;
import voxelman.events;
import voxelman.packets;
import voxelman.storage.chunk;
import voxelman.storage.coordinates;
import voxelman.storage.utils;
import voxelman.storage.worldaccess;
import voxelman.utils.math;
import voxelman.utils.trace : traceRay;

import voxelman.client.appstatistics;
import voxelman.client.chunkman;
import voxelman.client.events;

//version = manualGC;
version(manualGC) import core.memory;

version = profiling;

auto formatDuration(Duration dur)
{
	import std.string : format;
	auto splitted = dur.split();
	return format("%s.%03s,%03s secs",
		splitted.seconds, splitted.msecs, splitted.usecs);
}

final class ClientConnection : BaseClient{}

final class ClientPlugin : IPlugin
{
private:
	PluginManager pluginman = new PluginManager;
	ResourceManagerRegistry resmanRegistry = new ResourceManagerRegistry;

	// Plugins
	EventDispatcherPlugin evDispatcher;
	GraphicsPlugin graphics = new GraphicsPlugin;
	GuiPlugin guiPlugin = new GuiPlugin;
	InputPlugin input = new InputPlugin;
	MovementPlugin movementPlugin = new MovementPlugin;
	WorldInteractionPlugin worldInteraction = new WorldInteractionPlugin;
	EditPlugin editPlugin = new EditPlugin;

	// Resource managers
	Config config;
	KeyBindingManager keyBindingMan = new KeyBindingManager;

public:
	AppStatistics stats;

	// Game stuff
	ChunkMan chunkMan;
	WorldAccess worldAccess;
	ClientConnection connection;

	// Debug
	Widget debugInfo;
	Profiler profiler;
	DespikerSender profilerSender;
	bool isProfilerRunning;

	// Client data
	bool isRunning = false;
	bool isDisconnecting = false;
	bool isSpawned = false;
	bool mouseLocked;

	ConfigOption serverIpOpt;
	ConfigOption serverPortOpt;
	ConfigOption runDespikerOpt;
	ConfigOption numWorkersOpt;
	ConfigOption nicknameOpt;

	// Graphics stuff
	bool isCullingEnabled = true;
	bool doUpdateObserverPosition = true;
	vec3 updatedCameraPos;

	// Client id stuff
	ClientId myId;
	string[ClientId] clientNames;

	// Send position interval
	double sendPositionTimer = 0;
	enum sendPositionInterval = 0.1;
	ChunkWorldPos prevChunkPos;

	// IPlugin stuff
	override string name() @property { return "ClientPlugin"; }
	override string semver() @property { return "0.5.0"; }

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		serverIpOpt = config.registerOption!string("ip", "127.0.0.1");
		serverPortOpt = config.registerOption!ushort("port", 1234);
		runDespikerOpt = config.registerOption!bool("run_despiker", false);
		numWorkersOpt = config.registerOption!uint("num_workers", 4);
		nicknameOpt = config.registerOption!string("name", "Player");

		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_Q, "key.lockMouse", null, &onLockMouse));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_RIGHT_BRACKET, "key.incViewRadius", null, &onIncViewRadius));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_LEFT_BRACKET, "key.decViewRadius", null, &onDecViewRadius));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_C, "key.toggleCulling", null, &onToggleCulling));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_U, "key.togglePosUpdate", null, &onTogglePositionUpdate));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_F4, "key.stopServer", null, &onStopServerKey));
	}

	override void preInit()
	{
		loadEnet();

		connection = new ClientConnection;
		connection.connectHandler = &onConnect;
		connection.disconnectHandler = &onDisconnect;

		chunkMan.init(numWorkersOpt.get!uint);
		worldAccess.onChunkModifiedHandlers ~= &chunkMan.onChunkChanged;

		registerPackets(connection);
		//connection.printPacketMap();

		connection.registerPacketHandler!PacketMapPacket(&handlePacketMapPacket);
		connection.registerPacketHandler!SessionInfoPacket(&handleSessionInfoPacket);
		connection.registerPacketHandler!ClientLoggedInPacket(&handleUserLoggedInPacket);
		connection.registerPacketHandler!ClientLoggedOutPacket(&handleUserLoggedOutPacket);
		connection.registerPacketHandler!MessagePacket(&handleMessagePacket);
		connection.registerPacketHandler!ClientPositionPacket(&handleClientPositionPacket);
		connection.registerPacketHandler!ChunkDataPacket(&handleChunkDataPacket);
		connection.registerPacketHandler!MultiblockChangePacket(&handleMultiblockChangePacket);
		connection.registerPacketHandler!SpawnPacket(&handleSpawnPacket);
	}

	override void init(IPluginManager pluginman)
	{
		evDispatcher.subscribeToEvent(&onUpdateEvent);
		evDispatcher.subscribeToEvent(&onPostUpdateEvent);
		evDispatcher.subscribeToEvent(&drawScene);
		evDispatcher.subscribeToEvent(&drawOverlay);
		evDispatcher.subscribeToEvent(&onClosePressedEvent);
		evDispatcher.subscribeToEvent(&onGameStopEvent);
	}

	override void postInit()
	{
		updatedCameraPos = graphics.camera.position;
		chunkMan.updateObserverPosition(graphics.camera.position);
		ConnectionSettings settings = {null, 1, 2, 0, 0};

		connection.start(settings);
		static if (ENABLE_RLE_PACKET_COMPRESSION)
			enet_host_compress_with_range_coder(connection.host);
		connect();

		debugInfo = guiPlugin.context.getWidgetById("debugInfo");
		foreach(i; 0..12) guiPlugin.context.createWidget("label", debugInfo);
		guiPlugin.context.getWidgetById("stopServer").addEventHandler(&onStopServer);
		guiPlugin.context.getWidgetById("toggleProfiler").addEventHandler(
			(Widget w,PointerClickEvent e){toggleProfiler(); return true;}
		);
		guiPlugin.context.getWidgetById("connect").addEventHandler(
			(Widget w,PointerClickEvent e){connect(); return true;}
		);

		if (runDespikerOpt.get!bool)
				toggleProfiler();
	}

	bool onStopServer(Widget widget, PointerClickEvent event)
	{
		sendMessage("/stop");
		return true;
	}

	void printDebug()
	{
		// Print debug info
		auto lines = debugInfo.getPropertyAs!("children", Widget[]);
		string[] statStrings = stats.getFormattedOutput();

		lines[ 0]["text"] = statStrings[0].to!dstring;
		lines[ 1]["text"] = statStrings[1].to!dstring;

		lines[ 2]["text"] = statStrings[2].to!dstring;
		lines[ 3]["text"] = statStrings[3].to!dstring;
		stats.lastFrameLoadedChunks = stats.totalLoadedChunks;

		lines[ 4]["text"] = statStrings[4].to!dstring;
		lines[ 5]["text"] = statStrings[5].to!dstring;

		vec3 pos = graphics.camera.position;
		lines[ 6]["text"] = format("Pos: X %.2f, Y %.2f, Z %.2f",
			pos.x, pos.y, pos.z).to!dstring;

		ChunkWorldPos chunkPos = chunkMan.observerPosition;
		auto regionPos = RegionWorldPos(chunkPos);
		auto localChunkPosition = ChunkRegionPos(chunkPos);
		lines[ 7]["text"] = format("C: %s R: %s L: %s",
			chunkPos, regionPos, localChunkPosition).to!dstring;

		vec3 target = graphics.camera.target;
		vec2 heading = graphics.camera.heading;
		lines[ 8]["text"] = format("Heading: %.2f %.2f Target: X %.2f, Y %.2f, Z %.2f",
			heading.x, heading.y, target.x, target.y, target.z).to!dstring;
		lines[ 9]["text"] = format("Chunks to remove: %s",
			chunkMan.removeQueue.length).to!dstring;
		//lines[ 10]["text"] = format("Chunks to load: %s", chunkMan.numLoadChunkTasks).to!dstring;
		lines[ 11]["text"] = format("Chunks to mesh: %s", chunkMan.chunkMeshMan.numMeshChunkTasks).to!dstring;
	}

	this()
	{
		version(profiling)
		{
			ubyte[] storage  = new ubyte[Profiler.maxEventBytes + 20 * 1024 * 1024];
			profiler = new Profiler(storage);
		}
		profilerSender = new DespikerSender([profiler]);

		evDispatcher = new EventDispatcherPlugin(profiler);
		config = new Config(CLIENT_CONFIG_FILE_NAME);
		worldAccess = WorldAccess(&chunkMan.chunkStorage.getChunk, () => 0);
	}

	void registerPlugins()
	{
		pluginman.registerPlugin(guiPlugin);
		pluginman.registerPlugin(graphics);
		pluginman.registerPlugin(evDispatcher);
		pluginman.registerPlugin(input);
		pluginman.registerPlugin(worldInteraction);
		pluginman.registerPlugin(editPlugin);
		pluginman.registerPlugin(movementPlugin);
		pluginman.registerPlugin(this);
	}

	void registerResourceManagers()
	{
		resmanRegistry.registerResourceManager(config);
		resmanRegistry.registerResourceManager(keyBindingMan);
	}

	void load()
	{
		// register all plugins and managers
		registerPlugins();
		registerResourceManagers();

		// Actual loading sequence
		resmanRegistry.initResourceManagers();
		pluginman.registerResources(resmanRegistry);
		resmanRegistry.loadResources();
		resmanRegistry.postInitResourceManagers();
		pluginman.initPlugins();
	}

	void run(string[] args)
	{
		import std.datetime : TickDuration, Clock, usecs;
		import core.thread : Thread;

		version(manualGC) GC.disable;

		writeln("load1");
		load();
		writeln("load2");


		info("\nSystem info");
		foreach(item; guiPlugin.getHardwareInfo())
			info(item);

		TickDuration lastTime = Clock.currAppTick;
		TickDuration newTime = TickDuration.from!"seconds"(0);

		isRunning = true;
		while(isRunning)
		{
			Zone frameZone = Zone(profiler, "frame");

			newTime = Clock.currAppTick;
			double delta = (newTime - lastTime).usecs / 1_000_000.0;
			lastTime = newTime;

			{
				Zone subZone = Zone(profiler, "preUpdate");
				evDispatcher.postEvent(PreUpdateEvent(delta));
			}
			{
				Zone subZone = Zone(profiler, "update");
				evDispatcher.postEvent(UpdateEvent(delta));
			}
			{
				Zone subZone = Zone(profiler, "postUpdate");
				evDispatcher.postEvent(PostUpdateEvent(delta));
			}
			{
				Zone subZone = Zone(profiler, "render");
				evDispatcher.postEvent(RenderEvent());
			}
			{
				version(manualGC) {
					Zone subZone = Zone(profiler, "GC.collect()");
					GC.collect();
				}
			}
			{
				Zone subZone = Zone(profiler, "sleepAfterFrame");
				// time used in frame
				delta = (lastTime - Clock.currAppTick).usecs / 1_000_000.0;
				guiPlugin.fpsHelper.sleepAfterFrame(delta);
			}

			version(profiling) {
				frameZone.__dtor;
				profilerSender.update();
				if (profilerSender.sending != isProfilerRunning)
					toggleProfilerButton();
			}
		}
		profilerSender.reset();

		isDisconnecting = connection.isConnected;
		connection.disconnect();

		infof("disconnecting");
		while (isDisconnecting)
		{
			connection.update();
		}
		infof("stop");

		evDispatcher.postEvent(GameStopEvent());
	}

	void connect()
	{
		connection.connect(serverIpOpt.get!string, serverPortOpt.get!ushort);
	}

	void toggleProfiler()
	{
		if (profilerSender.sending)
			profilerSender.reset();
		else
		{
			import std.file : exists;
			if (exists(DESPIKER_PATH))
				profilerSender.startDespiker(DESPIKER_PATH);
			else
				warningf(`No despiker executable found at "%s"`, DESPIKER_PATH);
		}
		toggleProfilerButton();
	}

	void toggleProfilerButton()
	{
		isProfilerRunning = profilerSender.sending;
		dstring text = isProfilerRunning ? "Stop profiler" : "Start profiler";
		guiPlugin.context.getWidgetById("toggleProfiler").setProperty!dstring("text", text);
	}

	void onGameStopEvent(ref GameStopEvent gameStopEvent)
	{
		chunkMan.stop();
		thread_joinAll();
	}

	void onUpdateEvent(ref UpdateEvent event)
	{
		if (doUpdateObserverPosition)
		{
			updatedCameraPos = graphics.camera.position;
		}
		chunkMan.updateObserverPosition(updatedCameraPos);

		connection.update();
		chunkMan.update();
		if (doUpdateObserverPosition)
			sendPosition(event.deltaTime);

		updateStats();
		printDebug();
		stats.resetCounters();
	}

	void onPostUpdateEvent(ref PostUpdateEvent event)
	{
		connection.flush();
	}

	void sendPosition(double dt)
	{
		ChunkWorldPos chunkPos = BlockWorldPos(graphics.camera.position);

		if (isSpawned)
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

	void updateStats()
	{
		stats.fps = guiPlugin.fpsHelper.fps;
		stats.totalLoadedChunks = chunkMan.totalLoadedChunks;
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
		auto oldViewRadius = chunkMan.viewRadius;
		chunkMan.viewRadius = clamp(newViewRadius,
			MIN_VIEW_RADIUS, MAX_VIEW_RADIUS);

		if (oldViewRadius != chunkMan.viewRadius)
		{
			connection.send(ViewRadiusPacket(chunkMan.viewRadius));
		}
	}

	void sendMessage(string msg)
	{
		connection.send(MessagePacket(0, msg));
	}

	void onClosePressedEvent(ref ClosePressedEvent event)
	{
		isRunning = false;
	}

	void onLockMouse(string)
	{
		mouseLocked = !mouseLocked;
		if (mouseLocked)
			guiPlugin.window.mousePosition = cast(ivec2)(guiPlugin.window.size) / 2;
	}

	void onIncViewRadius(string)
	{
		incViewRadius();
	}

	void onDecViewRadius(string)
	{
		decViewRadius();
	}

	void onStopServerKey(string)
	{
		sendMessage("/stop");
	}

	void onToggleCulling(string)
	{
		isCullingEnabled = !isCullingEnabled;
	}

	void onTogglePositionUpdate(string)
	{
		doUpdateObserverPosition = !doUpdateObserverPosition;
	}

	void drawScene(ref Render1Event event)
	{
		Zone drawSceneZone = Zone(profiler, "drawScene");

		graphics.chunkShader.bind;
		glUniformMatrix4fv(graphics.viewLoc, 1, GL_FALSE,
			graphics.camera.cameraMatrix);
		glUniformMatrix4fv(graphics.projectionLoc, 1, GL_FALSE,
			cast(const float*)graphics.camera.perspective.arrayof);

		import dlib.geometry.aabb;
		import dlib.geometry.frustum;
		Matrix4f vp = graphics.camera.perspective * graphics.camera.cameraToClipMatrix;
		Frustum frustum;
		frustum.fromMVP(vp);

		Matrix4f modelMatrix;
		foreach(ChunkWorldPos cwp; chunkMan.chunkMeshMan.visibleChunks.items)
		{
			Chunk* c = chunkMan.getChunk(cwp);
			assert(c);
			++stats.chunksVisible;

			if (isCullingEnabled)
			{
				// Frustum culling
				ivec3 ivecMin = c.position.vector * CHUNK_SIZE;
				vec3 vecMin = vec3(ivecMin.x, ivecMin.y, ivecMin.z);
				vec3 vecMax = vecMin + CHUNK_SIZE;
				AABB aabb = boxFromMinMaxPoints(vecMin, vecMax);
				auto intersects = frustum.intersectsAABB(aabb);
				if (!intersects) continue;
			}

			modelMatrix = translationMatrix!float(c.mesh.position);
			glUniformMatrix4fv(graphics.modelLoc, 1, GL_FALSE, cast(const float*)modelMatrix.arrayof);

			c.mesh.bind;
			c.mesh.render;

			++stats.chunksRendered;
			stats.vertsRendered += c.mesh.numVertexes;
			stats.trisRendered += c.mesh.numTris;
		}

		glUniformMatrix4fv(graphics.modelLoc, 1, GL_FALSE, cast(const float*)Matrix4f.identity.arrayof);
		graphics.chunkShader.unbind;
	}

	void drawOverlay(ref Render2Event event)
	{
		event.renderer.setColor(Color(0,0,0,1));
		event.renderer.fillRect(Rect(guiPlugin.window.size.x/2-7, guiPlugin.window.size.y/2-1, 14, 2));
		event.renderer.fillRect(Rect(guiPlugin.window.size.x/2-1, guiPlugin.window.size.y/2-7, 2, 14));
	}

	void onConnect(ref ENetEvent event)
	{
		infof("Connection to %s:%s established", serverIpOpt.get!string, serverPortOpt.get!ushort);
		connection.send(ViewRadiusPacket(chunkMan.viewRadius));
	}

	void onDisconnect(ref ENetEvent event)
	{
		infof("disconnected with data %s", event.data);

		// Reset server's information
		event.peer.data = null;

		evDispatcher.postEvent(ThisClientDisconnectedEvent());
		isDisconnecting = false;
		isSpawned = false;
	}

	void handlePacketMapPacket(ubyte[] packetData, ClientId clientId)
	{
		auto packetMap = unpackPacket!PacketMapPacket(packetData);

		connection.setPacketMap(packetMap.packetNames);
		//connection.printPacketMap();

		connection.send(LoginPacket(nicknameOpt.get!string));
		evDispatcher.postEvent(ThisClientConnectedEvent());
	}

	void handleSessionInfoPacket(ubyte[] packetData, ClientId clientId)
	{
		auto loginInfo = unpackPacket!SessionInfoPacket(packetData);

		clientNames = loginInfo.clientNames;
		myId = loginInfo.yourId;
		evDispatcher.postEvent(ThisClientLoggedInEvent(myId));
	}

	void handleUserLoggedInPacket(ubyte[] packetData, ClientId clientId)
	{
		auto newUser = unpackPacket!ClientLoggedInPacket(packetData);
		clientNames[newUser.clientId] = newUser.clientName;
		infof("%s has connected", newUser.clientName);
		evDispatcher.postEvent(ClientLoggedInEvent(clientId));
	}

	void handleUserLoggedOutPacket(ubyte[] packetData, ClientId clientId)
	{
		auto packet = unpackPacket!ClientLoggedOutPacket(packetData);
		infof("%s has disconnected", clientName(packet.clientId));
		evDispatcher.postEvent(ClientLoggedOutEvent(clientId));
		clientNames.remove(packet.clientId);
	}

	void handleMessagePacket(ubyte[] packetData, ClientId clientId)
	{
		auto msg = unpackPacket!MessagePacket(packetData);
		if (msg.clientId == 0)
			infof("%s", msg.msg);
		else
			infof("%s> %s", clientName(msg.clientId), msg.msg);
		evDispatcher.postEvent(ChatMessageEvent(msg.clientId, msg.msg));
	}

	void handleClientPositionPacket(ubyte[] packetData, ClientId peer)
	{
		import voxelman.utils.math : nansToZero;

		auto packet = unpackPacket!ClientPositionPacket(packetData);
		tracef("Received ClientPositionPacket(%s, %s)",
			packet.pos, packet.heading);

		nansToZero(packet.pos);
		graphics.camera.position = packet.pos;

		nansToZero(packet.heading);
		graphics.camera.setHeading(packet.heading);
	}

	void handleSpawnPacket(ubyte[] packetData, ClientId peer)
	{
		auto packet = unpackPacket!SpawnPacket(packetData);
		isSpawned = true;
	}

	void handleChunkDataPacket(ubyte[] packetData, ClientId peer)
	{
		auto packet = unpackPacket!ChunkDataPacket(packetData);
		//tracef("Received %s ChunkDataPacket(%s,%s)", packetData.length,
		//	packet.chunkPos, packet.blockData.blocks.length);
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

	string clientName(ClientId clientId)
	{
		return clientId in clientNames ? clientNames[clientId] : format("? %s", clientId);
	}
}
