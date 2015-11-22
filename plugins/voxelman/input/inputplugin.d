/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.input.inputplugin;

import std.experimental.logger;
import dlib.math.vector;

import pluginlib;
import voxelman.gui.guiplugin;
import voxelman.input.keybindingmanager;


shared static this()
{
	pluginRegistry.regClientPlugin(new InputPlugin);
}

final class InputPlugin : IPlugin
{
	GuiPlugin guiPlugin;
	KeyBindingManager keyBindingsMan;

	mixin IdAndSemverFrom!(voxelman.input.plugininfo);

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
	}

	override void postInit()
	{
		guiPlugin.window.keyPressed.connect(&onKeyPressed);
		guiPlugin.window.keyReleased.connect(&onKeyReleased);
		guiPlugin.window.mousePressed.connect(&onMousePressed);
		guiPlugin.window.mouseReleased.connect(&onMouseReleased);
	}

	void onKeyPressed(uint keyCode)
	{
		if (auto binding = keyCode in keyBindingsMan.keyBindingsByCode)
		{
			KeyBinding* b = *binding;
			if (b.pressHandler)
				b.pressHandler(b.keyName);
		}
	}

	void onKeyReleased(uint keyCode)
	{
		if (auto binding = keyCode in keyBindingsMan.keyBindingsByCode)
		{
			KeyBinding* b = *binding;
			if (b.releaseHandler)
				b.releaseHandler(b.keyName);
		}
	}

	void onMousePressed(uint keyCode)
	{
		if (auto binding = keyCode in keyBindingsMan.keyBindingsByCode)
		{
			KeyBinding* b = *binding;
			if (b.pressHandler)
				b.pressHandler(b.keyName);
		}
	}

	void onMouseReleased(uint keyCode)
	{
		if (auto binding = keyCode in keyBindingsMan.keyBindingsByCode)
		{
			KeyBinding* b = *binding;
			if (b.releaseHandler)
				b.releaseHandler(b.keyName);
		}
	}

	bool isKeyPressed(string keyName)
	{
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
}
