module modular.modules.mainloopmodule;

import modular;

import modular.modules.eventdispatchermodule;

/// Updatable module interaface.
/// Look at MainLoopModule.registerUpdatableModule(IUpdatableModule)
interface IUpdatableModule
{
	/// Will be called by MainLoopModule every frame
	void update(double delta);
}

interface IMainLoopModule
{
	void registerUpdatableModule(IUpdatableModule updatableModule);
	bool isRunning() @property;
	bool isRunning(bool newIsRunning) @property;
}

class GameStopEvent : Event
{

}

/// Module where the main loop is located
class MainLoopModule : IMainLoopModule, IModule
{
	override string name() @property { return "MainLoopModule"; }
	override string semver() @property { return "0.1.0"; }
	override void load() {}

	override void init(IModuleManager moduleman)
	{
		evdisp = moduleman.getModule!EventDispatcherModule(this);
	}

private:
	EventDispatcherModule evdisp;
	IUpdatableModule[] updatableModules;
	bool _isRunning;

public:

	// There is an option to auto-register all modules found in IModuleManager
	// if they can be cast to IUpdatableModule
	override void registerUpdatableModule(IUpdatableModule updatableModule)
	{
		updatableModules ~= updatableModule;
	}

	/// Main loop execution condition. Will run if true.
	override bool isRunning() @property
	{
		return _isRunning;
	}

	/// ditto
	override bool isRunning(bool newIsRunning) @property
	{
		return _isRunning = newIsRunning;
	}

	/// Simple main loop
	void mainLoop()
	{
		import std.datetime : TickDuration, Clock, usecs;
		import core.thread : Thread;

		isRunning = true;

		TickDuration lastTime = Clock.currAppTick;
		TickDuration newTime = TickDuration.from!"seconds"(0);

		while(isRunning)
		{
			newTime = Clock.currAppTick;
			double delta = (newTime - lastTime).usecs / 1_000_000.0;
			lastTime = newTime;
			update(delta);
		}

		// loop stop
		// event example
		evdisp.postEvent(new GameStopEvent);
	}

	private void update(double delta)
	{
		foreach(mod; updatableModules)
		{
			mod.update(delta);
		}
	}
}