/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.client.clientmodule;

import dlib.math.vector : uvec2;

import modular;

import voxelman.modules.eventdispatchermodule;
import voxelman.modules.graphicsmodule;

import voxelman.chunkman;
import voxelman.events;
import voxelman.config;


final class ClientModule : IModule
{
	// Game stuff
	ChunkMan chunkMan;
	
	EventDispatcherModule evDispatcher;
	GraphicsModule graphics;
	
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
}