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

import plugin;
import plugin.pluginmanager;
import netlib.connection;
import netlib.baseclient;

import voxelman.plugins.eventdispatcherplugin;
import voxelman.plugins.graphicsplugin;
import voxelman.plugins.guiplugin;

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
	EventDispatcherPlugin evDispatcher = new EventDispatcherPlugin;
	GraphicsPlugin graphics = new GraphicsPlugin;
	GuiPlugin guiPlugin = new GuiPlugin;
	Config config;

public:
	AppStatistics stats;

	// Game stuff
	ChunkMan chunkMan;
	WorldAccess worldAccess;

	ClientConnection connection;

	// Debug
	Widget debugInfo;

	// Client data
	bool isRunning = false;
	bool isSpawned = false;
	bool mouseLocked;
	bool autoMove;
	ConfigOption serverIp;
	ConfigOption serverPort;

	// Graphics stuff
	bool isCullingEnabled = true;
	bool doUpdateObserverPosition = true;

	// Client id stuff
	ClientId myId;
	string myName = "client_name";
	string[ClientId] clientNames;

	// Cursor rendering stuff
	vec3 cursorPos, cursorSize = vec3(1.02, 1.02, 1.02);
	vec3 lineStart, lineEnd;
	bool cursorHit;
	bool showCursor;
	BlockWorldPos blockPos;
	vec3 hitPosition;
	ivec3 hitNormal;
	Duration cursorTraceTime;
	Batch debugBatch;
	Batch traceBatch;
	Batch hitBatch;

	// Send position interval
	double sendPositionTimer = 0;
	enum sendPositionInterval = 0.1;
	ChunkWorldPos prevChunkPos;

	// IPlugin stuff
	override string name() @property { return "ClientPlugin"; }
	override string semver() @property { return "0.5.0"; }

	override void loadConfig(Config config)
	{
		serverIp = config.registerOption!string("ip", "127.0.0.1");
		serverPort = config.registerOption!ushort("port", 1234);
	}

	override void preInit()
	{
		loadEnet();

		connection = new ClientConnection;
		connection.connectHandler = &onConnect;
		connection.disconnectHandler = &onDisconnect;

		chunkMan.init();
		worldAccess.onChunkModifiedHandlers ~= &chunkMan.onChunkChanged;

		registerPackets(connection);
		//connection.printPacketMap();

		connection.registerPacketHandler!SessionInfoPacket(&handleSessionInfoPacket);
		connection.registerPacketHandler!ClientLoggedInPacket(&handleUserLoggedInPacket);
		connection.registerPacketHandler!ClientLoggedOutPacket(&handleUserLoggedOutPacket);
		connection.registerPacketHandler!MessagePacket(&handleMessagePacket);
		connection.registerPacketHandler!ClientPositionPacket(&handleClientPositionPacket);
		connection.registerPacketHandler!ChunkDataPacket(&handleChunkDataPacket);
		connection.registerPacketHandler!MultiblockChangePacket(&handleMultiblockChangePacket);
	}

	override void init(IPluginManager pluginman)
	{
		graphics = pluginman.getPlugin!GraphicsPlugin(this);

		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin(this);
		evDispatcher.subscribeToEvent(&onPreUpdateEvent);
		evDispatcher.subscribeToEvent(&onUpdateEvent);
		evDispatcher.subscribeToEvent(&drawScene);
		evDispatcher.subscribeToEvent(&onClosePressedEvent);
		evDispatcher.subscribeToEvent(&onGameStopEvent);
	}

	override void postInit()
	{
		chunkMan.updateObserverPosition(graphics.camera.position);
		connect();
		guiPlugin.window.keyReleased.connect(&keyReleased);
		guiPlugin.window.mouseReleased.connect(&mouseReleased);

		debugInfo = guiPlugin.context.getWidgetById("debugInfo");
		foreach(i; 0..12) guiPlugin.context.createWidget("label", debugInfo);
		guiPlugin.context.getWidgetById("stopServer").addEventHandler(&onStopServer);
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
		config = new Config(CLIENT_CONFIG_FILE_NAME);
		worldAccess = WorldAccess(&chunkMan.chunkStorage.getChunk, () => 0);
	}

	void run(string[] args)
	{
		import std.datetime : TickDuration, Clock, usecs;
		import core.thread : Thread;

		version(manualGC) GC.disable;

		pluginman.registerPlugin(guiPlugin);
		pluginman.registerPlugin(graphics);
		pluginman.registerPlugin(evDispatcher);
		pluginman.registerPlugin(this);

		pluginman.loadConfig(config);
		config.load();
		pluginman.initPlugins();

		TickDuration lastTime = Clock.currAppTick;
		TickDuration newTime = TickDuration.from!"seconds"(0);

		isRunning = true;
		while(isRunning)
		{
			newTime = Clock.currAppTick;
			double delta = (newTime - lastTime).usecs / 1_000_000.0;
			lastTime = newTime;

			evDispatcher.postEvent(new PreUpdateEvent(delta));
			evDispatcher.postEvent(new UpdateEvent(delta));
			evDispatcher.postEvent(new PostUpdateEvent(delta));
			graphics.draw();

			version(manualGC) GC.collect();

			// time used in frame
			delta = (lastTime - Clock.currAppTick).usecs / 1_000_000.0;
			guiPlugin.fpsHelper.sleepAfterFrame(delta);
		}

		connection.disconnect();

		while (connection.isRunning && connection.isConnected)
		{
			connection.update(0);
		}

		evDispatcher.postEvent(new GameStopEvent);
	}

	void placeBlock(BlockType blockId)
	{
		if (chunkMan.blockMan.blocks[blockId].isVisible)
		{
			blockPos.vector += hitNormal;
		}

		//infof("hit %s, blockPos %s, hitPosition %s, hitNormal %s\ntime %s",
		//	cursorHit, blockPos, hitPosition, hitNormal,
		//	cursorTraceTime.formatDuration);

		cursorPos = vec3(blockPos.vector) - vec3(0.005, 0.005, 0.005);
		lineStart = graphics.camera.position;
		lineEnd = graphics.camera.position + graphics.camera.target * 40;

		if (cursorHit)
		{
			hitBatch = traceBatch;
			traceBatch = Batch();

			showCursor = true;
			connection.send(PlaceBlockPacket(blockPos.vector, blockId));
		}
		else
		{
			showCursor = false;
		}
	}

	void connect()
	{
		ConnectionSettings settings = {null, 1, 2, 0, 0};

		connection.start(settings);
		static if (ENABLE_RLE_PACKET_COMPRESSION)
			enet_host_compress_with_range_coder(connection.host);
		connection.connect(serverIp.get!string, serverPort.get!ushort);
	}

	void onGameStopEvent(GameStopEvent gameStopEvent)
	{
		chunkMan.stop();
		thread_joinAll();
	}

	void onUpdateEvent(UpdateEvent event)
	{
		if (doUpdateObserverPosition)
			chunkMan.updateObserverPosition(graphics.camera.position);

		if (connection.isRunning)
			connection.update(0);

		chunkMan.update();

		ChunkWorldPos chunkPos = BlockWorldPos(graphics.camera.position);
		if (isSpawned)
		{
			sendPositionTimer += event.deltaTime;
			if (sendPositionTimer > sendPositionInterval ||
				chunkPos != prevChunkPos)
			{
				sendPosition();
				if (sendPositionTimer < sendPositionInterval)
					sendPositionTimer = 0;
				else
					sendPositionTimer -= sendPositionInterval;
			}
		}

		prevChunkPos = chunkPos;

		traceCursor();
		drawDebugCursor();
		updateStats();
		printDebug();
		stats.resetCounters();
	}

	void traceCursor()
	{
		StopWatch sw;
		sw.start();

		auto isBlockSolid = (ivec3 blockWorldPos) {
			return chunkMan
				.blockMan
				.blocks[worldAccess.getBlock(BlockWorldPos(blockWorldPos))]
				.isVisible;
		};

		traceBatch.reset();

		cursorHit = traceRay(
			isBlockSolid,
			graphics.camera.position,
			graphics.camera.target,
			80.0, // max distance
			hitPosition,
			hitNormal,
			traceBatch);

		blockPos = BlockWorldPos(hitPosition);
		cursorTraceTime = cast(Duration)sw.peek;
	}

	void drawDebugCursor()
	{
		if (showCursor)
		{
			traceBatch.putCube(cursorPos, cursorSize, Colors.black, false);
			traceBatch.putLine(lineStart, lineEnd, Colors.black);
		}

		debugBatch.putCube(
				vec3(blockPos.vector) - vec3(0.005, 0.005, 0.005),
				cursorSize, Colors.red, false);
		debugBatch.putCube(
				vec3(blockPos.vector+hitNormal) - vec3(0.005, 0.005, 0.005),
				cursorSize, Colors.blue, false);
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

	void sendPosition()
	{
		connection.send(ClientPositionPacket(
			graphics.camera.position,
			graphics.camera.heading));
	}

	void sendMessage(string msg)
	{
		connection.send(MessagePacket(0, msg));
	}

	void onClosePressedEvent(ClosePressedEvent event)
	{
		isRunning = false;
	}

	void onPreUpdateEvent(PreUpdateEvent event)
	{
		if(mouseLocked)
		{
			ivec2 mousePos = guiPlugin.window.mousePosition;
			mousePos -= cast(ivec2)(guiPlugin.window.size) / 2;

			// scale, so up and left is positive, as rotation is anti-clockwise
			// and coordinate system is right-hand and -z if forward
			mousePos *= -1;

			if(mousePos.x !=0 || mousePos.y !=0)
			{
				graphics.camera.rotate(vec2(mousePos));
			}
			guiPlugin.window.mousePosition = cast(ivec2)(guiPlugin.window.size) / 2;

			uint cameraSpeed = 10;
			vec3 posDelta = vec3(0,0,0);
			if(guiPlugin.window.isKeyPressed(KeyCode.KEY_LEFT_SHIFT)) cameraSpeed = 60;

			if(guiPlugin.window.isKeyPressed(KeyCode.KEY_D)) posDelta.x = 1;
			else if(guiPlugin.window.isKeyPressed(KeyCode.KEY_A)) posDelta.x = -1;

			if(guiPlugin.window.isKeyPressed(KeyCode.KEY_W)) posDelta.z = 1;
			else if(guiPlugin.window.isKeyPressed(KeyCode.KEY_S)) posDelta.z = -1;

			if(guiPlugin.window.isKeyPressed(KeyCode.KEY_SPACE)) posDelta.y = 1;
			else if(guiPlugin.window.isKeyPressed(KeyCode.KEY_LEFT_CONTROL)) posDelta.y = -1;

			if (posDelta != vec3(0))
			{
				posDelta.normalize();
				posDelta *= cameraSpeed * event.deltaTime;
				graphics.camera.moveAxis(posDelta);
			}
		}
		// TODO: remove after bug is found
		else if (autoMove)
		{
			// Automoving
			graphics.camera.moveAxis(vec3(0,0,20)*event.deltaTime);
		}
	}

	void keyReleased(uint keyCode)
	{
		switch(keyCode)
		{
			case KeyCode.KEY_Q: mouseLocked = !mouseLocked;
				if (mouseLocked)
					guiPlugin.window.mousePosition = cast(ivec2)(guiPlugin.window.size) / 2;
				break;
			case KeyCode.KEY_P: graphics.camera.printVectors; break;
			//case KeyCode.KEY_I:

			//	chunkMan
			//	.regionStorage
			//	.getChunkStoreInfo(chunkMan.observerPosition)
			//	.writeln("\n");
			//	break;
			case KeyCode.KEY_M:
				break;
			case KeyCode.KEY_U:
				doUpdateObserverPosition = !doUpdateObserverPosition; break;
			case KeyCode.KEY_C: isCullingEnabled = !isCullingEnabled; break;
			case KeyCode.KEY_R: graphics.resetCamera(); break;
			case KeyCode.KEY_F4: sendMessage("/stop"); break;
			case KeyCode.KEY_LEFT_BRACKET: decViewRadius(); break;
			case KeyCode.KEY_RIGHT_BRACKET: incViewRadius(); break;

			default: break;
		}
	}

	void mouseReleased(uint mouseButton)
	{
		if (mouseLocked)
		switch(mouseButton)
		{
			case PointerButton.PB_1:
				placeBlock(1);
				break;
			case PointerButton.PB_2:
				placeBlock(2);
				break;
			default:break;
		}
	}

	void drawScene(Draw1Event event)
	{
		glEnable(GL_DEPTH_TEST);

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
		foreach(Chunk* c; chunkMan.visibleChunks)
		{
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

		graphics.debugDraw.draw(debugBatch);
		//graphics.debugDraw.draw(hitBatch);
		debugBatch.reset();

		graphics.chunkShader.unbind;

		glDisable(GL_DEPTH_TEST);

		event.renderer.setColor(Color(0,0,0,1));
		event.renderer.fillRect(Rect(guiPlugin.window.size.x/2-7, guiPlugin.window.size.y/2-1, 14, 2));
		event.renderer.fillRect(Rect(guiPlugin.window.size.x/2-1, guiPlugin.window.size.y/2-7, 2, 14));
	}

	void onConnect(ref ENetEvent event)
	{
		infof("Connection to %s:%s established", serverIp.get!string, serverPort.get!ushort);
		connection.send(LoginPacket(myName));
		evDispatcher.postEvent(new ThisClientConnectedEvent);
	}

	void onDisconnect(ref ENetEvent event)
	{
		infof("disconnected with data %s", event.data);

		// Reset server's information
		event.peer.data = null;

		evDispatcher.postEvent(new ThisClientDisconnectedEvent);
	}

	void handleSessionInfoPacket(ubyte[] packetData, ClientId clientId)
	{
		auto loginInfo = unpackPacket!SessionInfoPacket(packetData);

		clientNames = loginInfo.clientNames;
		myId = loginInfo.yourId;
		evDispatcher.postEvent(new ThisClientLoggedInEvent(myId));
	}

	void handleUserLoggedInPacket(ubyte[] packetData, ClientId clientId)
	{
		auto newUser = unpackPacket!ClientLoggedInPacket(packetData);
		clientNames[newUser.clientId] = newUser.clientName;
		infof("%s has connected", newUser.clientName);
		evDispatcher.postEvent(new ClientLoggedInEvent(clientId));
	}

	void handleUserLoggedOutPacket(ubyte[] packetData, ClientId clientId)
	{
		auto packet = unpackPacket!ClientLoggedOutPacket(packetData);
		infof("%s has disconnected", clientName(packet.clientId));
		evDispatcher.postEvent(new ClientLoggedOutEvent(clientId));
		clientNames.remove(packet.clientId);
	}

	void handleMessagePacket(ubyte[] packetData, ClientId clientId)
	{
		auto msg = unpackPacket!MessagePacket(packetData);
		if (msg.clientId == 0)
			infof("%s", msg.msg);
		else
			infof("%s> %s", clientName(msg.clientId), msg.msg);
		evDispatcher.postEvent(new ChatMessageEvent(msg.clientId, msg.msg));
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
