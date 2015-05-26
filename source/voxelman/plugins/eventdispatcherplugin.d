module voxelman.plugins.eventdispatcherplugin;

import plugin;
import voxelman.config;

// Basic event
abstract class GameEvent
{
	bool continuePropagation = true;
}

private alias EventHandler = void delegate(GameEvent event);

class EventDispatcherPlugin : IPlugin
{
	override string name() @property { return "EventDispatcherPlugin"; }
	override string semver() @property { return "0.3.0"; }

	void subscribeToEvent(E : GameEvent)(void delegate(E event) handler)
	{
		_eventHandlers[typeid(E)] ~= cast(EventHandler)handler;
	}

	void postEvent(E : GameEvent)(E event)
	{
		auto handlers = typeid(E) in _eventHandlers;
		if (!handlers) return;

		GameEvent e = cast(GameEvent)event;
		foreach(handler; *handlers)
		{
			handler(e);
			if (!e.continuePropagation) break;
		}
	}

private:

	EventHandler[][TypeInfo] _eventHandlers;
}
