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
import netlib.connection;
import netlib.baseclient;

import voxelman.plugins.eventdispatcherplugin;
import voxelman.plugins.graphicsplugin;

import voxelman.config;
import voxelman.events;
import voxelman.packets;
import voxelman.storage.chunk;
import voxelman.storage.utils;
import voxelman.storage.worldaccess;
import voxelman.utils.math;
import voxelman.utils.trace;

import voxelman.client.appstatistics;
import voxelman.client.chunkman;
import voxelman.client.events;

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
	AppStatistics stats;

	// Game stuff
	ChunkMan chunkMan;
	WorldAccess worldAccess;

	ClientConnection connection;

	IWindow window;
	EventDispatcherPlugin evDispatcher;
	GraphicsPlugin graphics;

	bool isCullingEnabled = true;
	bool doUpdateObserverPosition = true;
	bool isSpawned = false;

	ClientId myId;
	string myName = "client_name";
	string[ClientId] clientNames;

	// shows AABB of hovered block
	vec3 cursorPos, cursorSize = vec3(1.02, 1.02, 1.02);
	vec3 lineStart, lineEnd;
	bool cursorHit;
	bool showCursor;
	BlockType blockType;
	ivec3 blockPos;
	vec3 hitPosition;
	ivec3 hitNormal;
	Duration cursorTraceTime;

	double sendPositionTimer = 0;
	enum sendPositionInterval = 0.1;
	ivec3 prevChunkPos;

	string clientName(ClientId clientId)
	{
		return clientId in clientNames ? clientNames[clientId] : format("? %s", clientId);
	}

	this(IWindow window)
	{
		this.window = window;
		worldAccess = WorldAccess(&chunkMan.chunkStorage.getChunk, () => 0);
	}


	// IPlugin stuff
	override string name() @property { return "ClientPlugin"; }
	override string semver() @property { return "0.3.0"; }
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
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin(this);
		graphics = pluginman.getPlugin!GraphicsPlugin(this);
		evDispatcher.subscribeToEvent(&update);
		evDispatcher.subscribeToEvent(&drawScene);
	}

	override void postInit()
	{
		chunkMan.updateObserverPosition(graphics.camera.position);
		connect();
	}

	void placeBlock(BlockType blockId)
	{
		if (chunkMan.blockMan.blocks[blockId].isVisible)
		{
			blockPos += hitNormal;
		}

		//infof("hit %s, blockPos %s, blockType %s, hitPosition %s, hitNormal %s time %s",
		//	cursorHit, blockPos, blockType, hitPosition, hitNormal,
		//	cursorTraceTime.formatDuration);

		cursorPos = vec3(blockPos) - vec3(0.005, 0.005, 0.005);
		lineStart = graphics.camera.position;
		lineEnd = graphics.camera.position + graphics.camera.target * 40;

		if (cursorHit)
		{
			showCursor = true;
			connection.send(PlaceBlockPacket(blockPos, blockId));
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
		connection.connect(CONNECT_ADDRESS, CONNECT_PORT);
	}

	void unload()
	{
		connection.disconnect();
		chunkMan.stop();
		thread_joinAll();
	}

	void update(UpdateEvent event)
	{
		if (doUpdateObserverPosition)
			chunkMan.updateObserverPosition(graphics.camera.position);

		if (connection.isRunning)
			connection.update(0);

		chunkMan.update();

		ivec3 chunkPos = worldToChunkPos(graphics.camera.position);
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
		if (showCursor)
		{
			graphics.debugDraw.drawCube(
				cursorPos, cursorSize, Colors.black, false);
			graphics.debugDraw.drawLine(lineStart, lineEnd, Colors.black);
		}
	}

	void traceCursor()
	{
		StopWatch sw;
		sw.start();

		cursorHit = traceRay(&worldAccess,
			&chunkMan.blockMan,
			graphics.camera.position,
			graphics.camera.target,
			40.0, // max distance
			blockType,
			hitPosition,
			hitNormal,
			1e-3);

		blockPos = hitPosition;
		cursorTraceTime = cast(Duration)sw.peek;

		graphics.debugDraw.drawCube(
				vec3(blockPos) - vec3(0.005, 0.005, 0.005), cursorSize, Colors.red, false);
		graphics.debugDraw.drawCube(
				vec3(blockPos+hitNormal) - vec3(0.005, 0.005, 0.005), cursorSize, Colors.blue, false);
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
				ivec3 ivecMin = c.coord * CHUNK_SIZE;
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
		graphics.debugDraw.flush();

		graphics.chunkShader.unbind;

		glDisable(GL_DEPTH_TEST);

		event.renderer.setColor(Color(0,0,0,1));
		event.renderer.fillRect(Rect(graphics.windowSize.x/2-7, graphics.windowSize.y/2-1, 14, 2));
		event.renderer.fillRect(Rect(graphics.windowSize.x/2-1, graphics.windowSize.y/2-7, 2, 14));
	}

	void onConnect(ref ENetEvent event)
	{
		infof("Connection to %s:%s established", CONNECT_ADDRESS, CONNECT_PORT);
		connection.send(LoginPacket(myName));
		evDispatcher.postEvent(new ThisClientConnectedEvent);
	}

	void onDisconnect(ref ENetEvent event)
	{
		infof("disconnected with data %s", event.data);

		// Reset server's information
		event.peer.data = null;

		connection.isRunning = false;
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
		chunkMan.onChunkLoaded(packet.chunkPos, packet.blockData);
	}

	void handleMultiblockChangePacket(ubyte[] packetData, ClientId peer)
	{
		auto packet = unpackPacket!MultiblockChangePacket(packetData);
		Chunk* chunk = chunkMan.chunkStorage.getChunk(packet.chunkPos);
		// We can receive data for chunk that is already deleted.
		if (chunk is null || chunk.isMarkedForDeletion)
			return;
		chunkMan.onChunkChanged(chunk, packet.blockChanges);
	}
}
