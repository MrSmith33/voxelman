/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.client.clientmodule;

import anchovy.gui;
import dlib.math.vector : uvec2;
import dlib.math.matrix : Matrix4f;
import dlib.math.affine : translationMatrix;

import modular;

import voxelman.modules.eventdispatchermodule;
import voxelman.modules.graphicsmodule;

import voxelman.events;
import voxelman.config;
import voxelman.chunk;

import voxelman.client.appstatistics;
import voxelman.client.chunkman;


final class ClientModule : IModule
{
	AppStatistics stats;

	// Game stuff
	ChunkMan chunkMan;
	
	EventDispatcherModule evDispatcher;
	GraphicsModule graphics;
	
	bool isCullingEnabled = true;
	bool doUpdateObserverPosition = true;


	// IModule stuff
	override string name() @property { return "ClientModule"; }
	override string semver() @property { return "0.3.0"; }
	override void preInit()
	{
		chunkMan.init();
	}
	
	override void init(IModuleManager moduleman)
	{
		evDispatcher = moduleman.getModule!EventDispatcherModule(this);
		graphics = moduleman.getModule!GraphicsModule(this);
		evDispatcher.subscribeToEvent(&update);
		evDispatcher.subscribeToEvent(&drawScene);
	}

	override void postInit()
	{
		chunkMan.updateObserverPosition(graphics.fpsController.camera.position);
	}

	void unload()
	{
		chunkMan.stop();
	}

	void update(UpdateEvent event)
	{
		chunkMan.update();
		if (doUpdateObserverPosition)
			chunkMan.updateObserverPosition(graphics.fpsController.camera.position);
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
}