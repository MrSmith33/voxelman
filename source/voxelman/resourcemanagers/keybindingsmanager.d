/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.resourcemanagers.keybindingsmanager;

import std.experimental.logger;

import resource;
import voxelman.resourcemanagers.config;
import voxelma.utils.keynamemap;
public import voxelman.plugins.guiplugin : KeyCode, PointerButton;


struct KeyBinding
{
	uint keyCode;
	string keyName;
	KeyHandler pressHandler;
	KeyHandler releaseHandler;
}

alias KeyHandler = void delegate(string key);

final class KeyBindingManager : IResourceManager
{
	KeyBinding*[uint] keyBindingsByCode;
	KeyBinding*[string] keyBindingsByName;
	ConfigOption[string] options;
	Config config;

	override string name() @property { return "KeyBindingManager"; }
	override string semver() @property { return "0.5.0"; }

	override void init(IResourceManagerRegistry resmanRegistry)
	{
		config = resmanRegistry.getResourceManager!Config;
	}

	// Load all keybindings from config
	override void postInit()
	{
		foreach(pair; options.byKeyValue)
		{
			string optionName = pair.key;
			ConfigOption option = pair.value;
			if (optionName !in keyBindingsByName) continue;

			KeyBinding* binding = keyBindingsByName[optionName];
			string key = option.get!string;
			if (key !in stringToKeyMap) continue;

			uint configKeyCode = stringToKeyMap[key];
			if (binding.keyCode != configKeyCode)
			{
				keyBindingsByCode.remove(binding.keyCode);
				keyBindingsByCode[configKeyCode] = binding;
				binding.keyCode = configKeyCode;
			}
		}
	}

	// Called during IPlugin.registerResources calls.
	void registerKeyBinding(KeyBinding* binding)
	{
		assert(binding);
		auto option = config.registerOption!string(binding.keyName, keyToStringMap[binding.keyCode]);
		options[binding.keyName] = option;
		keyBindingsByCode[binding.keyCode] = binding;
		keyBindingsByName[binding.keyName] = binding;

		//infof("Regiseterd key binding %s", *binding);
	}
}
