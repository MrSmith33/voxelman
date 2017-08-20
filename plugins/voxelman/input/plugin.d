/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.input.plugin;

import voxelman.log;
import voxelman.math;

import pluginlib;
import voxelman.gui.plugin;
import voxelman.input.keybindingmanager;
import voxelman.dbg.plugin;


final class InputPlugin : IPlugin
{
	GuiPlugin guiPlugin;
	KeyBindingManager keyBindingsMan;

	mixin IdAndSemverFrom!"voxelman.input.plugininfo";

	override void registerResourceManagers(void delegate(IResourceManager) registerRM)
	{
		registerRM(new KeyBindingManager);
	}

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		keyBindingsMan = resmanRegistry.getResourceManager!KeyBindingManager;
	}

	override void init(IPluginManager pluginman)
	{
		guiPlugin = pluginman.getPlugin!GuiPlugin;

		auto debugClient = pluginman.getPlugin!DebugClient;
		debugClient.registerDebugGuiHandler(&showDebugInput, DEBUG_ORDER, "Input");
	}

	override void postInit()
	{
		guiPlugin.window.keyPressed.connect(&onKeyPressed);
		guiPlugin.window.keyReleased.connect(&onKeyReleased);
		guiPlugin.window.mousePressed.connect(&onMousePressed);
		guiPlugin.window.mouseReleased.connect(&onMouseReleased);
	}

	void onKeyPressed(KeyCode keyCode, uint modifiers)
	{
		if (guiPlugin.igState.keyboardCaptured) return;
		if (auto binding = keyCode in keyBindingsMan.keyBindingsByCode)
		{
			KeyBinding* b = *binding;
			if (b.pressHandler)
				b.pressHandler(b.keyName);
		}
	}

	void onKeyReleased(KeyCode keyCode, uint modifiers)
	{
		if (guiPlugin.igState.keyboardCaptured) return;
		if (auto binding = keyCode in keyBindingsMan.keyBindingsByCode)
		{
			KeyBinding* b = *binding;
			if (b.releaseHandler)
				b.releaseHandler(b.keyName);
		}
	}

	void onMousePressed(PointerButton button, uint modifiers)
	{
		if (guiPlugin.igState.mouseCaptured) return;
		if (auto binding = button in keyBindingsMan.keyBindingsByCode)
		{
			KeyBinding* b = *binding;
			if (b.pressHandler)
				b.pressHandler(b.keyName);
		}
	}

	void onMouseReleased(PointerButton button, uint modifiers)
	{
		if (guiPlugin.igState.mouseCaptured) return;
		if (auto binding = button in keyBindingsMan.keyBindingsByCode)
		{
			KeyBinding* b = *binding;
			if (b.releaseHandler)
				b.releaseHandler(b.keyName);
		}
	}

	bool isKeyPressed(string keyName)
	{
		if (guiPlugin.igState.keyboardCaptured) return false;
		if (auto binding = keyName in keyBindingsMan.keyBindingsByName)
		{
			KeyBinding* b = *binding;
			return guiPlugin.window.isKeyPressed(b.keyCode);
		}
		else
			return false;
	}

	ivec2 mousePosition() @property
	{
		return guiPlugin.window.mousePosition;
	}

	ivec2 mousePosition(ivec2 newMousePosition) @property
	{
		guiPlugin.window.mousePosition = newMousePosition;
		return guiPlugin.window.mousePosition;
	}

	private void showDebugInput()
	{
		import derelict.glfw3.glfw3;
		import derelict.imgui.imgui;
		import voxelman.text.textformatter;
		import std.string : fromStringz;

		if (igCollapsingHeader("Input"))
		{
			if (igTreeNode("Joystick"))
			{
				foreach(joy; GLFW_JOYSTICK_1..GLFW_JOYSTICK_LAST+1)
				{
					if (glfwJoystickPresent(joy))
					{
						const char* name = glfwGetJoystickName(joy);
						auto strName = makeFormattedTextPtrs("Joystick %s: %s", joy, fromStringz(name));
						if (igTreeNode(strName.start))
						{
							int count;

							const float* axes = glfwGetJoystickAxes(joy, &count);
							auto strAxes = makeFormattedTextPtrs("Axes: %s", count);
							if (igTreeNode(strAxes.start))
							{
								foreach(i, axis; axes[0..count])
								{
									igTextf("%s: %.2f", i, axis);
								}
								igTreePop();
							}

							ubyte* buttons = glfwGetJoystickButtons(joy, &count);
							auto strButtons = makeFormattedTextPtrs("Buttons: %s", count);
							if (igTreeNode(strButtons.start))
							{
								foreach(i, button; buttons[0..count])
								{
									igTextf("%s: %s", i, button);
								}
								igTreePop();
							}
							igTreePop();
						}
					}
				}
				igTreePop();
			}
		}
	}
}
