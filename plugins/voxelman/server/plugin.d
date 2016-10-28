/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.server.plugin;

import voxelman.log;
import std.datetime : MonoTime, Duration, msecs, usecs, dur;

import pluginlib;
import pluginlib.pluginmanager;

import voxelman.core.config;
import voxelman.core.events;

import voxelman.eventdispatcher.plugin : EventDispatcherPlugin;
import voxelman.command.plugin;


//version = manualGC;
version(manualGC) import core.memory;

shared static this()
{
	auto s = new ServerPlugin;
	pluginRegistry.regServerPlugin(s);
	pluginRegistry.regServerMain(&s.run);
}

struct WorldSaveInternalEvent {}

enum ServerMode
{
	dedicated,
	internal
}

class ServerPlugin : IPlugin
{
private:
	PluginManager pluginman;
	EventDispatcherPlugin evDispatcher;

public:
	ServerMode mode;
	bool isRunning = false;
	bool isAutosaveEnabled = true;
	Duration autosavePeriod = dur!"seconds"(10);
	MonoTime lastSaveTime;

	mixin IdAndSemverFrom!(voxelman.server.plugininfo);

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;

		auto commandPlugin = pluginman.getPlugin!CommandPluginServer;
		commandPlugin.registerCommand("sv_stop|stop", &onStopCommand);
		commandPlugin.registerCommand("save", &onSaveCommand);
	}

	void onStopCommand(CommandParams) { isRunning = false; }
	void onSaveCommand(CommandParams) { save(); }

	void load(string[] args)
	{
		pluginman = new PluginManager;
		// register all plugins and managers
		import voxelman.pluginlib.plugininforeader : filterEnabledPlugins;
		foreach(p; pluginRegistry.serverPlugins.byValue.filterEnabledPlugins(args))
		{
			pluginman.registerPlugin(p);
		}
		// Actual loading sequence
		pluginman.initPlugins();
	}

	void run(string[] args, bool dedicated)
	{
		import core.thread : Thread, thread_joinAll;
		import core.memory;

		infof("Server thread: %s", Thread.getThis.id);

		if (dedicated)
			mode = ServerMode.dedicated;
		else
			mode = ServerMode.internal;

		load(args);
		infof("Starting game...");
		evDispatcher.postEvent(GameStartEvent());
		infof("[Running]");

		MonoTime prevTime = MonoTime.currTime;
		Duration frameTime = SERVER_FRAME_TIME_USECS.usecs;
		lastSaveTime = MonoTime.currTime;

		version(manualGC) GC.disable();

		// Main loop
		isRunning = true;
		import voxelman.client.servercontrol : isServerRunning;
		while (isRunning && isServerRunning())
		{
			MonoTime newTime = MonoTime.currTime;
			double delta = (newTime - prevTime).total!"usecs" / 1_000_000.0;
			prevTime = newTime;

			evDispatcher.postEvent(PreUpdateEvent(delta));
			evDispatcher.postEvent(UpdateEvent(delta));
			evDispatcher.postEvent(PostUpdateEvent(delta));
			autosave(MonoTime.currTime);

			version(manualGC)
			{
				auto collectStartTime = MonoTime.currTime;
				GC.collect();
				GC.minimize();
				auto collectDur = MonoTime.currTime - collectStartTime;
				//if (collectDur > 50.msecs)
				//	infof("GC.collect() time %s", collectDur);
			}

			Duration updateTime = MonoTime.currTime - newTime;
			Duration sleepTime = frameTime - updateTime;
			if (sleepTime > Duration.zero)
				Thread.sleep(sleepTime);
		}
		infof("Saving...");
		save();
		infof("Stopping...");
		evDispatcher.postEvent(GameStopEvent());

		if (mode == ServerMode.dedicated)
		{
			thread_joinAll();
		}
		infof("[Stopped]");
	}

	void autosave(MonoTime now)
	{
		if (isAutosaveEnabled && now - lastSaveTime >= autosavePeriod) {
			lastSaveTime = now;
			save();
		}
	}

	void save()
	{
		evDispatcher.postEvent(WorldSaveInternalEvent());
	}
}
