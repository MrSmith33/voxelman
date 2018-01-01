/**
Copyright: Copyright (c) 2013-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.utils.fpshelper;

import core.thread;
import voxelman.utils.signal;

/++
 + Helper for measuring frames per second and setting static FPS.
 + Usually needs to be located as field of game class.
 +/
struct FpsHelper
{
	Signal!(FpsHelper*) fpsUpdated;

	/// fps will be updated each updateInterval seconds
	double updateInterval = 0.5;

	/// Stores actual FPS value
	double fps = 0;

	/// Stores update time passed trough update every updateInterval
	double updateTime = 0;

	/// Stores last delta time passed into update()
	double deltaTime = 0;

	/// Stores amount of updates between
	size_t fpsTicks;

	/// Accumulates time before reaching update interval
	double secondsAccumulator = 0;

	bool limitFps = true;

	uint maxFps = 60;

	/// Delta time value will clamped to meet interval [0;timeLimit].
	/// This can prevent from value lags when entering hibernation or resizing the window.
	double timeLimit = 1;

	void update(double dt, double updateTime)
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
			this.updateTime = updateTime;
			secondsAccumulator -= updateInterval;
			fpsTicks = 0;
			fpsUpdated.emit(&this);
		}
	}

	void sleepAfterFrame(double frameTime)
	{
		if (limitFps)
		{
			uint msecs = cast(uint)((1/cast(double)maxFps - frameTime)*1000);
			if (msecs > 0)
				Thread.sleep(dur!"msecs"(msecs));
		}
	}
}

