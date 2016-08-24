/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.movement.plugin;

import std.experimental.logger;

import voxelman.math;

import pluginlib;
import voxelman.core.events;

import voxelman.client.plugin;
import voxelman.config.configmanager : ConfigOption, ConfigManager;
import voxelman.eventdispatcher.plugin;
import voxelman.graphics.plugin;
import voxelman.gui.plugin;
import voxelman.input.plugin;
import voxelman.input.keybindingmanager;

shared static this()
{
	pluginRegistry.regClientPlugin(new MovementPlugin);
}

class MovementPlugin : IPlugin
{
	ClientPlugin clientPlugin;
	EventDispatcherPlugin evDispatcher;
	GraphicsPlugin graphics;
	GuiPlugin guiPlugin;
	InputPlugin input;

	bool autoMove;
	ConfigOption cameraSpeedOpt;
	ConfigOption cameraBoostOpt;

	mixin IdAndSemverFrom!(voxelman.movement.plugininfo);

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto keyBindingMan = resmanRegistry.getResourceManager!KeyBindingManager;
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_W, "key.forward"));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_A, "key.left"));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_S, "key.backward"));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_D, "key.right"));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_SPACE, "key.up"));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_LEFT_CONTROL, "key.down"));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_LEFT_SHIFT, "key.fast"));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_KP_ADD, "key.speed_up", null, &speedUp));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_KP_SUBTRACT, "key.speed_down", null, &speedDown));

		ConfigManager config = resmanRegistry.getResourceManager!ConfigManager;
		cameraSpeedOpt = config.registerOption!int("camera_speed", 20);
		cameraBoostOpt = config.registerOption!int("camera_boost", 5);
	}

	override void init(IPluginManager pluginman)
	{
		clientPlugin = pluginman.getPlugin!ClientPlugin;
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		graphics = pluginman.getPlugin!GraphicsPlugin;
		guiPlugin = pluginman.getPlugin!GuiPlugin;
		input = pluginman.getPlugin!InputPlugin;

		evDispatcher.subscribeToEvent(&onPreUpdateEvent);
	}

	void speedUp(string) {
		cameraSpeedOpt.set(clamp(cameraSpeedOpt.get!uint + 1, 1, 20));
	}
	void speedDown(string)	 {
		cameraSpeedOpt.set(clamp(cameraSpeedOpt.get!uint - 1, 1, 20));
	}

	void onPreUpdateEvent(ref PreUpdateEvent event)
	{
		if(clientPlugin.mouseLocked)
		{
			ivec2 mousePos = input.mousePosition;
			mousePos -= cast(ivec2)(guiPlugin.window.size) / 2;

			// scale, so up and left is positive, as rotation is anti-clockwise
			// and coordinate system is right-hand and -z if forward
			mousePos *= -1;

			if(mousePos.x !=0 || mousePos.y !=0)
			{
				graphics.camera.rotate(vec2(mousePos));
			}
			input.mousePosition = cast(ivec2)(guiPlugin.window.size) / 2;

			uint cameraSpeed = cameraSpeedOpt.get!uint;
			vec3 posDelta = vec3(0,0,0);
			if(input.isKeyPressed("key.fast")) cameraSpeed *= cameraBoostOpt.get!uint;

			if(input.isKeyPressed("key.right")) posDelta.x = 1;
			else if(input.isKeyPressed("key.left")) posDelta.x = -1;

			if(input.isKeyPressed("key.forward")) posDelta.z = 1;
			else if(input.isKeyPressed("key.backward")) posDelta.z = -1;

			if(input.isKeyPressed("key.up")) posDelta.y = 1;
			else if(input.isKeyPressed("key.down")) posDelta.y = -1;

			if (posDelta != vec3(0))
			{
				posDelta.normalize();
				posDelta *= cameraSpeed * event.deltaTime;
				graphics.camera.moveAxis(posDelta);
			}
		}
		// TODO: remove after bug is found
		else if (autoMove)
		{
			// Automoving
			graphics.camera.moveAxis(vec3(0,0,20)*event.deltaTime);
		}
	}
}
