module voxelman.eventdispatcher.plugin;

import pluginlib;
import voxelman.core.config;

abstract class GameEvent {
}

template isGameEvent(T)
{
	enum bool isGameEvent = is(typeof(
    (inout int = 0)
    {
    	T t;
    }));
}

private class ValidGameEventClass : GameEvent {}
private struct ValidGameEvent {}
static assert(isGameEvent!ValidGameEvent);
static assert(isGameEvent!ValidGameEventClass);

private alias EventHandler = void delegate(ref GameEvent event);

shared static this()
{
	pluginRegistry.regClientPlugin(new EventDispatcherPlugin);
	pluginRegistry.regServerPlugin(new EventDispatcherPlugin);
}

class EventDispatcherPlugin : IPlugin
{
	mixin IdAndSemverFrom!(voxelman.eventdispatcher.plugininfo);

	void subscribeToEvent(Event)(void delegate(ref Event event) handler)
	{
		static assert(isGameEvent!Event);
		_eventHandlers[typeid(Event)] ~= cast(EventHandler)handler;
	}

	void postEvent(Event)(auto ref Event event)
	{
		static assert(isGameEvent!Event);
		auto handlers = typeid(Event) in _eventHandlers;
		if (!handlers) return;

		foreach(handler; *handlers)
		{
			(cast(void delegate(ref Event))handler)(event);
		}
	}

private:

	EventHandler[][TypeInfo] _eventHandlers;
}
