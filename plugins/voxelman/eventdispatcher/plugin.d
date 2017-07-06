module voxelman.eventdispatcher.plugin;

import pluginlib;
import voxelman.core.config;

private alias EventHandler = void delegate(void* event);


class EventDispatcherPlugin : IPlugin
{
	mixin IdAndSemverFrom!"voxelman.eventdispatcher.plugininfo";

	void subscribeToEvent(Event)(void delegate(ref Event event) handler)
	{
		_eventHandlers[typeid(Event)] ~= cast(EventHandler)handler;
	}

	void postEvent(Event)(auto ref Event event)
	{
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
