/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.client.clientplugin;

import core.thread : thread_joinAll;

import anchovy.gui;
import anchovy.core.interfaces.iwindow;
import dlib.math.vector : uvec2;
import dlib.math.matrix : Matrix4f;
import dlib.math.affine : translationMatrix;
import derelict.enet.enet;

import plugin;
import netlib.connection;
import netlib.baseclient;

import voxelman.plugins.eventdispatcherplugin;
import voxelman.plugins.graphicsplugin;

import voxelman.events;
import voxelman.config;
import voxelman.chunk;
import voxelman.packets;
import voxelman.utils.math;

import voxelman.client.appstatistics;
import voxelman.client.chunkman;
import voxelman.client.events;

final class ClientConnection : BaseClient{}

final class ClientPlugin : IPlugin
{
	AppStatistics stats;

	// Game stuff
	ChunkMan chunkMan;
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
		chunkMan.updateObserverPosition(graphics.fpsController.camera.position);
		connect();
	}

	void placeBlock(BlockType blockId)
	{
		enum cursorDistance = 3;
		vec3 editCursorOffset = graphics.fpsController.camera.target * cursorDistance;
		editCursorOffset.x *= -1;
		editCursorOffset.y *= -1;
		vec3 editCursorPos = graphics.fpsController.camera.position + editCursorOffset;
		ivec3 blockPos = toivec3(editCursorPos);
		ivec3 chunkPos = worldToChunkPos(editCursorPos);
		writefln("editCursorPos %s chunkPos %s blockPos %s index %s",
			editCursorPos, chunkPos, blockPos, worldToChunkBlockIndex(editCursorPos));
		connection.send(
			MultiblockChangePacket(chunkPos,
				[BlockChange(worldToChunkBlockIndex(editCursorPos), blockId)]));
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
			chunkMan.updateObserverPosition(graphics.fpsController.camera.position);

		if (connection.isRunning)
			connection.update(0);

		chunkMan.update();

		ivec3 chunkPos = worldToChunkPos(graphics.fpsController.camera.position);
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
	}

	void sendPosition()
	{
		connection.send(ClientPositionPacket(
			graphics.fpsController.camera.position,
			graphics.fpsController.heading));
	}

	void drawScene(Draw1Event event)
	{
		glEnable(GL_DEPTH_TEST);

		graphics.chunkShader.bind;
		glUniformMatrix4fv(graphics.viewLoc, 1, GL_FALSE,
			graphics.fpsController.cameraMatrix);
		glUniformMatrix4fv(graphics.projectionLoc, 1, GL_FALSE,
			cast(const float*)graphics.fpsController.camera.perspective.arrayof);

		import dlib.geometry.aabb;
		import dlib.geometry.frustum;
		Matrix4f vp = graphics.fpsController.camera.perspective * graphics.fpsController.cameraToClipMatrix;
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
		graphics.chunkShader.unbind;

		glDisable(GL_DEPTH_TEST);

		event.renderer.setColor(Color(0,0,0,1));
		event.renderer.drawRect(Rect(graphics.windowSize.x/2-7, graphics.windowSize.y/2-1, 14, 2));
		event.renderer.drawRect(Rect(graphics.windowSize.x/2-1, graphics.windowSize.y/2-7, 2, 14));
	}

	void onConnect(ref ENetEvent event)
	{
		writefln("Connection to %s:%s established", CONNECT_ADDRESS, CONNECT_PORT);
		connection.send(LoginPacket(myName));
		evDispatcher.postEvent(new ThisClientConnectedEvent);
	}

	void onDisconnect(ref ENetEvent event)
	{
		writefln("disconnected with data %s", event.data);

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
		writefln("%s has connected", newUser.clientName);
		evDispatcher.postEvent(new ClientLoggedInEvent(clientId));
	}

	void handleUserLoggedOutPacket(ubyte[] packetData, ClientId clientId)
	{
		auto packet = unpackPacket!ClientLoggedOutPacket(packetData);
		writefln("%s has disconnected", clientName(packet.clientId));
		evDispatcher.postEvent(new ClientLoggedOutEvent(clientId));
		clientNames.remove(packet.clientId);
	}

	void handleMessagePacket(ubyte[] packetData, ClientId clientId)
	{
		auto msg = unpackPacket!MessagePacket(packetData);
		if (msg.clientId == 0)
			writefln("%s", msg.msg);
		else
			writefln("%s> %s", clientName(msg.clientId), msg.msg);
		evDispatcher.postEvent(new ChatMessageEvent(msg.clientId, msg.msg));
	}

	void handleClientPositionPacket(ubyte[] packetData, ClientId peer)
	{
		import voxelman.utils.math : nansToZero;

		auto packet = unpackPacket!ClientPositionPacket(packetData);
		writefln("Received ClientPositionPacket(%s, %s)",
			packet.pos, packet.heading);

		nansToZero(packet.pos);
		graphics.fpsController.camera.position = packet.pos;

		nansToZero(packet.heading);
		graphics.fpsController.setHeading(packet.heading);

		isSpawned = true;
	}

	void handleChunkDataPacket(ubyte[] packetData, ClientId peer)
	{
		auto packet = unpackPacket!ChunkDataPacket(packetData);
		//writefln("Received %s ChunkDataPacket(%s,%s)", packetData.length,
		//	packet.chunkPos, packet.chunkData.typeData.length);
		chunkMan.onChunkLoaded(packet.chunkPos, packet.chunkData);
	}

	void handleMultiblockChangePacket(ubyte[] packetData, ClientId peer)
	{
		auto packet = unpackPacket!MultiblockChangePacket(packetData);
		chunkMan.onChunkChanged(packet.chunkPos, packet.blockChanges);
	}
}
