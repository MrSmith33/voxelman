module modular.modules.eventdispatchermodule;

import modular;

// Basic event
abstract class Event
{
	bool continuePropagation = true;
}

private alias EventHandler = void delegate(Event event);

/// Event 
class EventDispatcherModule : IModule, IEventDispatcherModule
{
	override string name() @property { return "EventDispatcherModule"; }
	override string semver() @property { return "1.0.0"; }
	override void load() { }
	override void init(IModuleManager moduleman) {}

	void subscribeToEvent(E : Event)(void delegate(E event) handler)
	{
		_eventHandlers[typeid(E)] ~= cast(EventHandler)handler;
	}

	void postEvent(E : Event)(E event)
	{
		auto handlers = typeid(E) in _eventHandlers;
		if (!handlers) return;

		Event e = cast(Event)event;
		foreach(handler; *handlers)
		{
			handler(e);
			if (!e.continuePropagation) break;
		}
	}

private:

	EventHandler[][TypeInfo] _eventHandlers;
}