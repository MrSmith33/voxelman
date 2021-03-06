/**
Copyright: Copyright (c) 2015-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.server.plugin;

import voxelman.log;
import core.time : MonoTime, Duration, msecs, usecs, dur;

import pluginlib;

import voxelman.core.config;
import voxelman.core.events;

import voxelman.eventdispatcher.plugin : EventDispatcherPlugin;
import voxelman.command.plugin;


//version = manualGC;
version(manualGC) import core.memory;


class ServerPlugin : IPlugin
{
private:
	EventDispatcherPlugin evDispatcher;

public:
	ServerMode mode;
	bool isRunning = false;
	bool isAutosaveEnabled = true;
	Duration autosavePeriod = dur!"seconds"(10);
	MonoTime lastSaveTime;

	mixin IdAndSemverFrom!"voxelman.server.plugininfo";

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;

		auto commandPlugin = pluginman.getPlugin!CommandPluginServer;
		commandPlugin.registerCommand(CommandInfo("sv_stop|stop", &onStopCommand, null, "Stops the server"));
		commandPlugin.registerCommand(CommandInfo("save", &onSaveCommand, null, "Saves the world"));
	}

	void onStopCommand(CommandParams) { isRunning = false; }
	void onSaveCommand(CommandParams) { save(); }

	void run(string[] args, ServerMode serverMode)
	{
		import core.thread : Thread;
		import core.memory;

		mode = serverMode;

		infof("Starting game...");
		evDispatcher.postEvent(GameStartEvent());
		infof("[Running]");

		MonoTime prevTime = MonoTime.currTime;
		enum size_t SERVER_FRAME_TIME_USECS = 1_000_000 / SERVER_UPDATES_PER_SECOND;
		Duration frameTime = SERVER_FRAME_TIME_USECS.usecs;
		lastSaveTime = MonoTime.currTime;

		version(manualGC) GC.disable();

		// Main loop
		isRunning = true;
		import voxelman.thread.servercontrol : isServerRunning;
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
				if (mode == ServerMode.standalone)
				{
					auto collectStartTime = MonoTime.currTime;
					GC.collect();
					GC.minimize();
					auto collectDur = MonoTime.currTime - collectStartTime;
					//if (collectDur > 50.msecs)
					//	infof("GC.collect() time %s", collectDur);
				}
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
