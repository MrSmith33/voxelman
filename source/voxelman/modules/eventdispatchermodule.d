module voxelman.modules.eventdispatchermodule;

import modular;

// Basic event
abstract class GameEvent
{
	bool continuePropagation = true;
}

private alias EventHandler = void delegate(GameEvent event);

class EventDispatcherModule : IModule
{
	override string name() @property { return "EventDispatcherModule"; }
	override string semver() @property { return "1.0.0"; }
	override void preInit() { }
	override void init(IModuleManager moduleman) {}
	override void postInit() { }

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