/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.server.plugin;

import std.experimental.logger;

import tharsis.prof : Profiler, DespikerSender, Zone;

import netlib;
import pluginlib;
import pluginlib.pluginmanager;

import voxelman.core.config;
import voxelman.core.events;
import voxelman.net.events;

import voxelman.eventdispatcher.plugin : EventDispatcherPlugin;
import voxelman.command.plugin;


shared static this()
{
	auto s = new ServerPlugin;
	pluginRegistry.regServerPlugin(s);
	pluginRegistry.regServerMain(&s.run);
}

class ServerPlugin : IPlugin
{
private:
	PluginManager pluginman;
	EventDispatcherPlugin evDispatcher;

public:
	bool isRunning = false;

	mixin IdAndSemverFrom!(voxelman.server.plugininfo);

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;

		auto commandPlugin = pluginman.getPlugin!CommandPluginServer;
		commandPlugin.registerCommand("sv_stop|stop", &onStopCommand);
	}

	void onStopCommand(CommandParams) { isRunning = false; }

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

	void run(string[] args)
	{
		import std.datetime : TickDuration, Duration, Clock, usecs;
		import core.thread : Thread;
		import core.memory;

		load(args);
		evDispatcher.postEvent(GameStartEvent());

		TickDuration lastTime = Clock.currAppTick;
		TickDuration newTime;
		Duration frameTime = SERVER_FRAME_TIME_USECS.usecs;

		// Main loop
		isRunning = true;
		while (isRunning)
		{
			newTime = Clock.currAppTick;
			double delta = (newTime - lastTime).usecs / 1_000_000.0;
			lastTime = newTime;

			evDispatcher.postEvent(PreUpdateEvent(delta));
			evDispatcher.postEvent(UpdateEvent(delta));
			evDispatcher.postEvent(PostUpdateEvent(delta));

			GC.collect();

			// update time
			auto updateTime = Clock.currAppTick - newTime;
			auto sleepTime = frameTime - updateTime;
			if (sleepTime > Duration.zero)
				Thread.sleep(sleepTime);
		}
		evDispatcher.postEvent(GameStopEvent());
	}
}
