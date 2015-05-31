/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.client.plugins.movementplugin;

import std.experimental.logger;

import dlib.math.vector;

import plugin;
import voxelman.events;
import voxelman.client.clientplugin;
import voxelman.plugins.eventdispatcherplugin;
import voxelman.plugins.graphicsplugin;
import voxelman.plugins.guiplugin;
import voxelman.plugins.inputplugin;


class MovementPlugin : IPlugin
{
	ClientPlugin clientPlugin;
	EventDispatcherPlugin evDispatcher;
	GraphicsPlugin graphics;
	GuiPlugin guiPlugin;
	InputPlugin input;

	// IPlugin stuff
	override string name() @property { return "MovementPlugin"; }
	override string semver() @property { return "0.5.0"; }

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin(this);
		clientPlugin = pluginman.getPlugin!ClientPlugin(this);
		input = pluginman.getPlugin!InputPlugin(this);
		guiPlugin = pluginman.getPlugin!GuiPlugin(this);
		graphics = pluginman.getPlugin!GraphicsPlugin(this);

		evDispatcher.subscribeToEvent(&onPreUpdateEvent);
		input.registerKeyBinding(new KeyBinding(KeyCode.KEY_W, "key.forward"));
		input.registerKeyBinding(new KeyBinding(KeyCode.KEY_A, "key.left"));
		input.registerKeyBinding(new KeyBinding(KeyCode.KEY_S, "key.backward"));
		input.registerKeyBinding(new KeyBinding(KeyCode.KEY_D, "key.right"));
		input.registerKeyBinding(new KeyBinding(KeyCode.KEY_SPACE, "key.up"));
		input.registerKeyBinding(new KeyBinding(KeyCode.KEY_LEFT_CONTROL, "key.down"));
		input.registerKeyBinding(new KeyBinding(KeyCode.KEY_LEFT_SHIFT, "key.fast"));
	}

	void onPreUpdateEvent(PreUpdateEvent event)
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

			uint cameraSpeed = 10;
			vec3 posDelta = vec3(0,0,0);
			if(input.isKeyPressed("key.fast")) cameraSpeed = 60;

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
		else if (clientPlugin.autoMove)
		{
			// Automoving
			graphics.camera.moveAxis(vec3(0,0,20)*event.deltaTime);
		}
	}
}
