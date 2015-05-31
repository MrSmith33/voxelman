/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.plugins.inputplugin;

import std.experimental.logger;
import dlib.math.vector;

import plugin;
import voxelman.plugins.guiplugin;
public import voxelman.plugins.guiplugin : KeyCode, PointerButton;


struct KeyBinding
{
	uint keyCode;
	string keyName;
	KeyHandler pressHandler;
	KeyHandler releaseHandler;
}

alias KeyHandler = void delegate(string key);

final class InputPlugin : IPlugin
{
	GuiPlugin guiPlugin;

	KeyBinding*[uint] keyBindingsByCode;
	KeyBinding*[string] keyBindingsByName;

	// IPlugin stuff
	override string name() @property { return "InputPlugin"; }
	override string semver() @property { return "0.5.0"; }

	override void loadConfig(Config config)
	{
	}

	override void preInit()
	{
	}

	override void init(IPluginManager pluginman)
	{
		guiPlugin = pluginman.getPlugin!GuiPlugin(this);
	}

	override void postInit()
	{
		guiPlugin.window.keyPressed.connect(&onKeyPressed);
		guiPlugin.window.keyReleased.connect(&onKeyReleased);
		guiPlugin.window.mousePressed.connect(&onMousePressed);
		guiPlugin.window.mouseReleased.connect(&onMouseReleased);
	}

	void registerKeyBinding(KeyBinding* binding)
	{
		assert(binding);
		keyBindingsByCode[binding.keyCode] = binding;
		keyBindingsByName[binding.keyName] = binding;

		//infof("Regiseterd key binding %s", *binding);
	}

	void onKeyPressed(uint keyCode)
	{
		if (auto binding = keyCode in keyBindingsByCode)
		{
			KeyBinding* b = *binding;
			if (b.pressHandler)
				b.pressHandler(b.keyName);
		}
	}

	void onKeyReleased(uint keyCode)
	{
		if (auto binding = keyCode in keyBindingsByCode)
		{
			KeyBinding* b = *binding;
			if (b.releaseHandler)
				b.releaseHandler(b.keyName);
		}
	}

	void onMousePressed(uint keyCode)
	{
		if (auto binding = keyCode in keyBindingsByCode)
		{
			KeyBinding* b = *binding;
			if (b.pressHandler)
				b.pressHandler(b.keyName);
		}
	}

	void onMouseReleased(uint keyCode)
	{
		if (auto binding = keyCode in keyBindingsByCode)
		{
			KeyBinding* b = *binding;
			if (b.releaseHandler)
				b.releaseHandler(b.keyName);
		}
	}

	bool isKeyPressed(string keyName)
	{
		if (auto binding = keyName in keyBindingsByName)
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
}
