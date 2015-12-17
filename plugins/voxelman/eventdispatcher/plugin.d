module voxelman.eventdispatcher.plugin;

import pluginlib;
import voxelman.core.config;
import tharsis.prof : Profiler;

abstract class GameEvent {
	Profiler profiler;
	bool continuePropagation = true;
}

template isGameEvent(T)
{
	enum bool isGameEvent = is(typeof(
    (inout int = 0)
    {
    	T t;
    	t.profiler = new Profiler(null);
    	t.continuePropagation = true;
    }));
}

private class ValidGameEventClass : GameEvent {

}
private struct ValidGameEvent {
	Profiler profiler;
	bool continuePropagation = true;
}
private struct InvalidEvent1 {}
private struct InvalidEvent2 {Profiler profiler;}
private struct InvalidEvent3 {bool continuePropagation;}
static assert(isGameEvent!ValidGameEvent);
static assert(isGameEvent!ValidGameEventClass);
static assert(!isGameEvent!InvalidEvent1);
static assert(!isGameEvent!InvalidEvent2);
static assert(!isGameEvent!InvalidEvent3);

private alias EventHandler = void delegate(ref GameEvent event);

shared static this()
{
	pluginRegistry.regClientPlugin(new EventDispatcherPlugin);
	pluginRegistry.regServerPlugin(new EventDispatcherPlugin);
}

class EventDispatcherPlugin : IPlugin
{
	mixin IdAndSemverFrom!(voxelman.eventdispatcher.plugininfo);

	Profiler profiler;

	void subscribeToEvent(Event)(void delegate(ref Event event) handler)
	{
		static assert(isGameEvent!Event, Event.stringof ~ " must contain Profiler profiler; and bool continuePropagation;");
		_eventHandlers[typeid(Event)] ~= cast(EventHandler)handler;
	}

	void postEvent(Event)(auto ref Event event)
	{
		static assert(isGameEvent!Event, stringof(Event) ~ " must contain Profiler profiler; and bool continuePropagation;");
		auto handlers = typeid(Event) in _eventHandlers;
		if (!handlers) return;

		event.profiler = profiler;
		foreach(handler; *handlers)
		{
			(cast(void delegate(ref Event))handler)(event);
			if (!event.continuePropagation) break;
		}
	}

private:

	EventHandler[][TypeInfo] _eventHandlers;
}
