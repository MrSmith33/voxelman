/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module anchovy.fpshelper;

import core.thread;
import anchovy.signal;

/++
 + Helper for measuring frames per second and setting static FPS.
 + Usually needs to be located as field of game class.
 +/
struct FpsHelper
{
	Signal!(FpsHelper*) fpsUpdated;

	/// fps will be updated each updateInterval seconds
	float updateInterval = 0.5;

	/// Stores actual FPS value
	float fps = 0;

	/// Stores last delta time passed into update()
	float deltaTime;

	/// Stores amount of updates between
	size_t fpsTicks;

	/// Accumulates time before reaching update interval
	float secondsAccumulator = 0;

	bool limitFps = true;

	uint maxFps = 60;

	/// Delta time value will clamped to meet interval [0;timeLimit].
	/// This can prevent from value lags when entering hibernation or resizing the window.
	float timeLimit = 1;

	void update(float dt)
	{
		if (dt > timeLimit)
		{
			dt = timeLimit;
		}
		deltaTime = dt;

		++fpsTicks;
		secondsAccumulator += dt;

		if (secondsAccumulator >= updateInterval)
		{
			fps = fpsTicks/secondsAccumulator;
			secondsAccumulator -= updateInterval;
			fpsTicks = 0;
			fpsUpdated.emit(&this);
		}
	}

	void sleepAfterFrame(float frameTime)
	{
		if (limitFps)
		{
			uint msecs = cast(uint)((1/cast(float)maxFps - frameTime)*1000);
			Thread.sleep(dur!"msecs"(msecs>2? msecs - 1: msecs));
		}
	}
}

