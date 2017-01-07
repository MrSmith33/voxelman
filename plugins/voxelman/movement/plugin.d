/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.movement.plugin;

import voxelman.log;

import voxelman.math;
static import voxelman.math.utils;

import pluginlib;
import voxelman.core.events;

import voxelman.config.configmanager : ConfigOption, ConfigManager;
import voxelman.block.plugin;
import voxelman.eventdispatcher.plugin;
import voxelman.graphics.plugin;
import voxelman.gui.plugin;
import voxelman.input.plugin;
import voxelman.input.keybindingmanager;
import voxelman.world.clientworld;

import derelict.imgui.imgui;
import voxelman.utils.textformatter;


class MovementPlugin : IPlugin
{
	EventDispatcherPlugin evDispatcher;
	GraphicsPlugin graphics;
	GuiPlugin guiPlugin;
	InputPlugin input;
	BlockPluginClient blockPlugin;
	ClientWorld clientWorld;

	ConfigOption fpsCameraSpeedOpt;
	ConfigOption fpsCameraBoostOpt;
	ConfigOption flightCameraSpeedOpt;
	ConfigOption flightCameraBoostOpt;

	bool onGround;
	bool isFlying;
	bool noclip;
	float eyesHeight = 1.7;
	float height = 1.75;
	float radius = 0.25;

	float friction = 0.9;

	float jumpHeight = 1.5;
	float jumpTime = 0.3;

	// calculated each tick from jumpHeight and jumpTime
	float gravity = 1;
	float jumpSpeed = 1; // ditto

	vec3 speed = vec3(0,0,0);
	float maxFallSpeed = 100;
	float airSpeed = 2;

	mixin IdAndSemverFrom!"voxelman.movement.plugininfo";

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
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_F, "key.fly", null, &toggleFlying));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_N, "key.noclip", null, &toggleNoclip));

		ConfigManager config = resmanRegistry.getResourceManager!ConfigManager;
		fpsCameraSpeedOpt = config.registerOption!int("fps_camera_speed", 5);
		fpsCameraBoostOpt = config.registerOption!int("fps_camera_boost", 2);
		flightCameraSpeedOpt = config.registerOption!int("flight_camera_speed", 20);
		flightCameraBoostOpt = config.registerOption!int("flight_camera_boost", 5);
	}

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		graphics = pluginman.getPlugin!GraphicsPlugin;
		guiPlugin = pluginman.getPlugin!GuiPlugin;
		input = pluginman.getPlugin!InputPlugin;
		clientWorld = pluginman.getPlugin!ClientWorld;
		blockPlugin = pluginman.getPlugin!BlockPluginClient;

		evDispatcher.subscribeToEvent(&onPreUpdateEvent);
		evDispatcher.subscribeToEvent(&onPostUpdateEvent);
	}

	void speedUp(string) {
		if (isFlying)
			flightCameraSpeedOpt.set(clamp(flightCameraSpeedOpt.get!uint + 1, 1, 200));
		else
			fpsCameraSpeedOpt.set(clamp(fpsCameraSpeedOpt.get!uint + 1, 1, 100));
	}
	void speedDown(string) {
		if (isFlying)
			flightCameraSpeedOpt.set(clamp(flightCameraSpeedOpt.get!uint - 1, 1, 200));
		else
			fpsCameraSpeedOpt.set(clamp(fpsCameraSpeedOpt.get!uint - 1, 1, 100));
	}
	void toggleFlying(string) {
		isFlying = !isFlying;
	}
	void toggleNoclip(string) {
		noclip = !noclip;
	}

	void onPreUpdateEvent(ref PreUpdateEvent event)
	{
		if(guiPlugin.mouseLocked)
			handleMouse();

		if (isCurrentChunkLoaded())
		{
			gravity = (2*jumpHeight/(jumpTime*jumpTime));
			jumpSpeed = sqrt(2*gravity*jumpHeight);
			float delta = clamp(event.deltaTime, 0, 2);

			vec3 eyesDelta = vec3(0, eyesHeight, 0);
			vec3 legsPos = graphics.camera.position - eyesDelta;

			vec3 targetDelta;
			if (isFlying)
				targetDelta = handleFlight(speed, delta);
			else
				targetDelta = handleWalk(speed, delta);

			vec3 newLegsPos;

			if (noclip)
				newLegsPos = legsPos + targetDelta;
			else
				newLegsPos = movePlayer(legsPos, targetDelta, delta);

			graphics.camera.position = newLegsPos + eyesDelta;
			graphics.camera.isUpdated = false;
		}
	}

	void onPostUpdateEvent(ref PostUpdateEvent event)
	{
		igBegin("Debug");
			igTextf("on ground: %s", onGround);
			igTextf("speed: %s loaded: %s", speed.length, isCurrentChunkLoaded());
			igCheckbox("[N]oclip", &noclip);
			igCheckbox("[F]ly mode", &isFlying);
		igEnd();
	}

	bool isCurrentChunkLoaded()
	{
		bool inBorders = clientWorld
			.currentDimensionBorders
			.contains(clientWorld.observerPosition.ivector3);
		bool chunkLoaded = clientWorld
			.chunkManager
			.isChunkLoaded(clientWorld.observerPosition);
		return chunkLoaded || (!inBorders);
	}

	// returns position delta
	vec3 handleWalk(ref vec3 speed, float dt)
	{
		InputState state = gatherInputs();

		vec3 inputSpeed = vec3(0,0,0);
		vec3 inputAccel = vec3(0,0,0);

		uint cameraSpeed = fpsCameraSpeedOpt.get!uint;
		if (state.boost)
			cameraSpeed *= fpsCameraBoostOpt.get!uint;

		vec3 horInputs = vec3(state.inputs.x, 0, state.inputs.z);
		if (horInputs != vec3(0,0,0))
			horInputs.normalize();

		vec3 cameraMovement = toCameraCoordinateSystem(horInputs);

		if (onGround)
		{
			speed = vec3(0,0,0);

			if (state.jump)
			{
				speed.y = jumpSpeed;
				onGround = false;
			}

			if (dt > 0) {
				inputAccel.x = cameraMovement.x / dt;
				inputAccel.z = cameraMovement.z / dt;
			}

			inputAccel *= cameraSpeed;
		}
		else
		{
			inputSpeed = cameraMovement * airSpeed;
		}

		vec3 accel = vec3(0, -gravity, 0) + inputAccel;

		vec3 airFrictionAccel = vec3(0, limitingFriction(std_abs(speed.y), accel.y, maxFallSpeed), 0);

		vec3 fullAcceleration = airFrictionAccel + accel;
		speed += fullAcceleration * dt;
		vec3 targetDelta = (speed + inputSpeed) * dt;
		return targetDelta;
	}

	vec3 handleFlight(ref vec3 speed, float dt)
	{
		InputState state = gatherInputs();
		uint cameraSpeed = flightCameraSpeedOpt.get!uint;
		if (state.boost)
			cameraSpeed *= flightCameraBoostOpt.get!uint;

		vec3 inputs = vec3(state.inputs);
		if (inputs != vec3(0,0,0))
			inputs.normalize();

		vec3 inputSpeed = toCameraCoordinateSystem(inputs);
		inputSpeed *= cameraSpeed;
		vec3 targetDelta = inputSpeed * dt;

		return targetDelta;
	}

	static struct InputState
	{
		ivec3 inputs = ivec3(0,0,0);
		bool boost;
		bool jump;
		bool hasHoriInput;
	}

	InputState gatherInputs()
	{
		InputState state;
		if(guiPlugin.mouseLocked)
		{
			if(input.isKeyPressed("key.fast")) state.boost = true;

			if(input.isKeyPressed("key.right"))
			{
				state.inputs.x = 1;
				state.hasHoriInput = true;
			}
			else if(input.isKeyPressed("key.left"))
			{
				state.inputs.x = -1;
				state.hasHoriInput = true;
			}

			if(input.isKeyPressed("key.forward"))
			{
				state.inputs.z = 1;
				state.hasHoriInput = true;
			}
			else if(input.isKeyPressed("key.backward"))
			{
				state.inputs.z = -1;
				state.hasHoriInput = true;
			}

			if(input.isKeyPressed("key.up")) {
				state.inputs.y = 1;
				state.jump = true;
			} else if(input.isKeyPressed("key.down")) state.inputs.y = -1;
		}
		return state;
	}

	void handleMouse()
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
	}

	vec3 toCameraCoordinateSystem(vec3 vector)
	{
		vec3 rightVec = graphics.camera.rotationQuatHor.rotate(vec3(1,0,0));
		vec3 targetVec = graphics.camera.rotationQuatHor.rotate(vec3(0,0,-1));
		return rightVec * vector.x + vec3(0,1,0) * vector.y + targetVec * vector.z;
	}

	vec3 movePlayer(vec3 pos, vec3 delta, float dt)
	{
		float distance = delta.length;
		int num_steps = cast(int)ceil(distance * 2); // num cells moved
		if (num_steps == 0) return pos;

		vec3 move_step = delta / num_steps;

		onGround = false;

		foreach(i; 0..num_steps) {
			pos += move_step;
			vec3 speed_mult = collide(pos, radius, height);
			speed *= speed_mult;
		}

		return pos;
	}

	vec3 collide(ref vec3 point, float rad, float height)
	{
		ivec3 cell = ivec3(floor(point.x), floor(point.y), floor(point.z));
		vec3 speed_mult = vec3(1, 1, 1);

		Aabb body_aabb = Aabb(point+vec3(0, height/2, 0), vec3(rad, height/2, rad));

		foreach(dy; -1..ceil(height+1)) {
		foreach(dx; [0, -1, 1]) {
		foreach(dz; [0, -1, 1]) {
		ivec3 local_cell = cell + ivec3(dx, dy, dz);
		if (clientWorld.isBlockSolid(local_cell))
		{
			Aabb cell_aabb = Aabb(vec3(local_cell) + vec3(0.5,0.5,0.5), vec3(0.5,0.5,0.5));
			bool collides = cell_aabb.collides(body_aabb);
			if (collides)
			{
				vec3 vector = cell_aabb.intersectionSize(body_aabb);
				int min_component;
				if (vector.x < vector.y) {
					if (vector.x < vector.z) min_component = 0;
					else min_component = 2;
				} else {
					if (vector.y < vector.z) min_component = 1;
					else min_component = 2;
				}

				if (min_component == 0) // x
				{
					int dir = cell_aabb.pos.x < body_aabb.pos.x ? 1 : -1;
					body_aabb.pos.x = body_aabb.pos.x + vector.x * dir;
					speed_mult.x = 0;
				}
				else if (min_component == 1) // y
				{
					int dir = cell_aabb.pos.y < body_aabb.pos.y ? 1 : -1;
					body_aabb.pos.y = body_aabb.pos.y + vector.y * dir;
					speed_mult.y = 0;
					if (dir == 1)
					{
						onGround = true;
					}
				}
				else // z
				{
					int dir = cell_aabb.pos.z < body_aabb.pos.z ? 1 : -1;
					body_aabb.pos.z = body_aabb.pos.z + vector.z * dir;
					speed_mult.z = 0;
				}
			}
		}
		}
		}
		}

		point.x = body_aabb.pos.x;
		point.z = body_aabb.pos.z;
		point.y = body_aabb.pos.y - body_aabb.size.y;

		return speed_mult;
	}
}


V limitingFriction(V)(V currentSpeed, V currentAcceleration, float maxSpeed)
{
	float speedScalar = currentSpeed.length;
	float frictionMult = speedScalar / maxSpeed;
	V frictionAcceleraion = -currentAcceleration * frictionMult;
	return frictionAcceleraion;
}

float limitingFriction(float currentSpeed, float currentAcceleration, float maxSpeed)
{
	float frictionMult = currentSpeed / maxSpeed;
	float frictionAcceleraion = -currentAcceleration * frictionMult;
	return frictionAcceleraion;
}

struct Aabb
{
	vec3 pos;
	vec3 size;

	// returns collides, vector
	bool collides(Aabb other) {
		vec3 delta = (other.pos - pos).abs;
		vec3 min_distance = size + other.size;
		return delta.x < min_distance.x && delta.y < min_distance.y && delta.z < min_distance.z;
	}

	vec3 intersectionSize(Aabb other) {
		float x = pos.x - size.x;
		float y = pos.y - size.y;
		float z = pos.z - size.z;
		float x2 = x + size.x*2;
		float y2 = y + size.y*2;
		float z2 = z + size.z*2;

		float o_x = other.pos.x - other.size.x;
		float o_y = other.pos.y - other.size.y;
		float o_z = other.pos.z - other.size.z;
		float o_x2 = o_x + other.size.x*2;
		float o_y2 = o_y + other.size.y*2;
		float o_z2 = o_z + other.size.z*2;

		float x_min = max(x, o_x);
		float y_min = max(y, o_y);
		float z_min = max(z, o_z);
		float x_max = min(x2, o_x2);
		float y_max = min(y2, o_y2);
		float z_max = min(z2, o_z2);

		return vec3(x_max - x_min, y_max - y_min, z_max - z_min);
	}
}
