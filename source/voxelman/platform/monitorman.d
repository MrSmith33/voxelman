/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.platform.monitorman;

import derelict.glfw3.glfw3;
import voxelman.log;
import voxelman.math;

struct MonitorManager
{
	private void printMode(const ref GLFWvidmode mode) {
		int colorBits = mode.redBits + mode.greenBits + mode.blueBits;
		infof("%sx%sp, %sbit (%s%s%s), %sHz",
			mode.width, mode.height, colorBits,
			mode.redBits, mode.greenBits, mode.blueBits,
			mode.refreshRate);
	}

	private void printMonitor(GLFWmonitor* monitor, size_t index)
	{
		ivec2 monPos;
		glfwGetMonitorPos(monitor, &monPos.x, &monPos.y);

		ivec2 physSize;
		glfwGetMonitorPhysicalSize(monitor, &physSize.x, &physSize.y);

		const char* name = glfwGetMonitorName(monitor);

		import std.string : fromStringz;
		infof("Monitor[%s] %s '%s' pos %s phys size %s", index, monitor, cast(string)fromStringz(name), monPos, physSize);

		int count;
		const GLFWvidmode* modes = glfwGetVideoModes(monitor, &count);

		infof("Got %s modes", count);
		foreach(ref mode; modes[0..count])
		{
			printMode(mode);
		}
	}

	private void printMonitors()
	{
		GLFWmonitor* primaryMonitor = glfwGetPrimaryMonitor();
		infof("Primary monitor %s", primaryMonitor);

		int monCount;
		GLFWmonitor** monitors = glfwGetMonitors(&monCount);
		foreach(i, monitor; monitors[0..monCount])
		{
			printMonitor(monitor, i);
		}
	}
}
