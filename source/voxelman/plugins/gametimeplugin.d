/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.plugins.gametimeplugin;

import plugin;
import voxelman.config;
import voxelman.events;
import voxelman.plugins.eventdispatcherplugin;

///
class GameTimePlugin : IPlugin
{
private:
	EventDispatcherPlugin evDispatcher;
	TimestampType _currentTick;

public:

	override string name() @property { return "GameTimePlugin"; }
	override string semver() @property { return "0.4.0"; }
	override void preInit()
	{
		_currentTick = 0;
	}
	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin(this);
		evDispatcher.subscribeToEvent(&preUpdate);
	}
	override void postInit() {}

	void preUpdate(ref PreUpdateEvent event)
	{
		++_currentTick;
	}

	TimestampType currentTick() @property
	{
		return _currentTick;
	}
}
