/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.worldinteraction.plugin;

import std.experimental.logger;
import core.time;
import std.datetime : StopWatch;

import pluginlib;
import voxelman.core.config;
import voxelman.utils.trace : traceRay;

import voxelman.core.events;
import voxelman.core.packets;
import voxelman.storage.coordinates;

import voxelman.block.plugin;
import voxelman.eventdispatcher.plugin;
import voxelman.graphics.plugin;
import voxelman.input.plugin;
import voxelman.net.plugin;
import voxelman.world.clientworld;


shared static this()
{
	pluginRegistry.regClientPlugin(new WorldInteractionPlugin);
}

class WorldInteractionPlugin : IPlugin
{
	NetClientPlugin connection;
	EventDispatcherPlugin evDispatcher;
	GraphicsPlugin graphics;
	BlockPluginClient blockPlugin;
	ClientWorld clientWorld;

	// Cursor
	bool cursorHit;
	BlockWorldPos blockPos;
	BlockWorldPos sideBlockPos; // blockPos + hitNormal
	ivec3 hitNormal;

	// Cursor rendering stuff
	vec3 cursorPos, cursorSize = vec3(1.02, 1.02, 1.02);
	vec3 lineStart, lineEnd;
	bool traceVisible;
	bool showCursor = true;
	vec3 hitPosition;
	Duration cursorTraceTime;
	Batch traceBatch;
	Batch hitBatch;

	mixin IdAndSemverFrom!(voxelman.worldinteraction.plugininfo);

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

	void placeBlock(BlockId blockId)
	{
		if (blockPlugin.getBlocks()[blockId].isVisible)
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

			traceVisible = true;
			connection.send(PlaceBlockPacket(blockPos.vector, blockId));
		}
		else
		{
			traceVisible = false;
		}
	}

	void placeBlockAt(BlockId blockId, BlockWorldPos bwp)
	{
		connection.send(PlaceBlockPacket(bwp.vector, blockId));
	}

	BlockId pickBlock()
	{
		return clientWorld.worldAccess.getBlock(blockPos);
	}

	void traceCursor()
	{
		StopWatch sw;
		sw.start();

		auto isBlockSolid = (ivec3 blockWorldPos) {
			auto block = clientWorld.worldAccess.getBlock(BlockWorldPos(blockWorldPos));
			return blockPlugin.getBlocks()[block].isVisible;
		};

		traceBatch.reset();

		cursorHit = traceRay(
			isBlockSolid,
			graphics.camera.position,
			graphics.camera.target,
			200.0, // max distance
			hitPosition,
			hitNormal,
			traceBatch);

		blockPos = BlockWorldPos(hitPosition);
		sideBlockPos = BlockWorldPos(blockPos.vector + hitNormal);
		cursorTraceTime = cast(Duration)sw.peek;
	}

	void drawDebugCursor()
	{
		if (traceVisible)
		{
			traceBatch.putCube(cursorPos, cursorSize, Colors.black, false);
			traceBatch.putLine(lineStart, lineEnd, Colors.black);
		}

		if (showCursor)
		{
			graphics.debugBatch.putCube(
				vec3(blockPos.vector) - vec3(0.005, 0.005, 0.005),
				cursorSize, Colors.red, false);
			graphics.debugBatch.putCube(
				vec3(blockPos.vector+hitNormal) - vec3(0.005, 0.005, 0.005),
				cursorSize, Colors.blue, false);
		}
	}

	void drawDebug(ref Render1Event event)
	{
		//graphics.chunkShader.bind;
		//graphics.draw(hitBatch);
		//graphics.chunkShader.unbind;
	}
}
