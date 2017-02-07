/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.worldinteraction.plugin;

import voxelman.log;
import core.time;
import std.datetime : StopWatch;

import pluginlib;
import voxelman.math;
import voxelman.core.config;
import voxelman.utils.trace : traceRay;
import voxelman.world.block;

import voxelman.core.events;
import voxelman.core.packets;
import voxelman.world.storage.coordinates;
import voxelman.world.storage.worldbox;
import voxelman.world.blockentity.blockentityaccess;

import voxelman.block.plugin;
import voxelman.eventdispatcher.plugin;
import voxelman.graphics.plugin;
import voxelman.input.plugin;
import voxelman.net.plugin;
import voxelman.world.clientworld;


enum cursorSize = vec3(1.02, 1.02, 1.02);
enum cursorOffset = vec3(0.01, 0.01, 0.01);

class WorldInteractionPlugin : IPlugin
{
	NetClientPlugin connection;
	EventDispatcherPlugin evDispatcher;
	GraphicsPlugin graphics;
	BlockPluginClient blockPlugin;
	ClientWorld clientWorld;

	// Cursor
	bool cursorHit;
	bool cameraInSolidBlock;
	BlockWorldPos blockPos;
	BlockWorldPos sideBlockPos; // blockPos + hitNormal
	ivec3 hitNormal;

	// Cursor rendering stuff
	vec3 cursorPos;
	vec3 lineStart, lineEnd;
	bool traceVisible;
	ivec3 hitPosition;
	Duration cursorTraceTime;
	Batch traceBatch;
	Batch hitBatch;

	mixin IdAndSemverFrom!"voxelman.worldinteraction.plugininfo";

	override void init(IPluginManager pluginman)
	{
		connection = pluginman.getPlugin!NetClientPlugin;
		blockPlugin = pluginman.getPlugin!BlockPluginClient;
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		graphics = pluginman.getPlugin!GraphicsPlugin;
		clientWorld = pluginman.getPlugin!ClientWorld;

		evDispatcher.subscribeToEvent(&onUpdateEvent);
		evDispatcher.subscribeToEvent(&drawDebug);
	}

	void onUpdateEvent(ref UpdateEvent event)
	{
		traceCursor();
		drawDebugCursor();
	}

	BlockIdAndMeta pickBlock()
	{
		return clientWorld.worldAccess.getBlockIdAndMeta(blockPos);
	}

	void fillBox(WorldBox box, BlockId blockId, BlockMetadata blockMeta = 0)
	{
		connection.send(FillBlockBoxPacket(box, blockId, blockMeta));
	}

	void traceCursor()
	{
		StopWatch sw;
		sw.start();

		traceBatch.reset();

		cursorHit = traceRay(
			&clientWorld.isBlockSolid,
			graphics.camera.position,
			graphics.camera.target,
			600.0, // max distance
			hitPosition,
			hitNormal,
			traceBatch);

		if (cursorHit) {
			import std.math : floor;
			auto camPos = graphics.camera.position;
			auto camBlock = ivec3(cast(int)floor(camPos.x), cast(int)floor(camPos.y), cast(int)floor(camPos.z));
			cameraInSolidBlock = BlockWorldPos(camBlock, 0) == BlockWorldPos(hitPosition, 0);
		} else {
			cameraInSolidBlock = false;
		}

		blockPos = BlockWorldPos(hitPosition, clientWorld.currentDimension);
		sideBlockPos = BlockWorldPos(blockPos.xyz + hitNormal, clientWorld.currentDimension);
		cursorTraceTime = cast(Duration)sw.peek;
	}

	void drawDebugCursor()
	{
		if (traceVisible)
		{
			traceBatch.putCube(cursorPos, cursorSize, Colors.black, false);
			traceBatch.putLine(lineStart, lineEnd, Colors.black);
		}
	}

	void drawCursor(BlockWorldPos block, Color4ub color)
	{
		graphics.debugBatch.putCube(
			vec3(block.xyz) - cursorOffset,
			cursorSize, color, false);
	}

	void drawDebug(ref RenderSolid3dEvent event)
	{
		//graphics.draw(hitBatch);
	}
}
