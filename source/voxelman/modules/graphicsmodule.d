/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.modules.graphicsmodule;

import dlib.math.vector : uvec2;
import modular;
import voxelman.config;
import voxelman.utils.fpscontroller;
import voxelman.utils.camera;

final class GraphicsModule : IModule
{
	override string name() @property { return "GraphicsModule"; }
	override string semver() @property { return "0.3.0"; }
	override void preInit()
	{
		fpsController.move(START_POS);
		fpsController.camera.sensivity = CAMERA_SENSIVITY;

		fpsController.camera.aspect = cast(float)windowSize.x/windowSize.y;
		fpsController.camera.updateProjection();
	}

	override void init(IModuleManager moduleman) { }

	override void postInit() { }

	void resetCamera()
	{
		fpsController.camera.position=vec3(0,0,0);
		fpsController.camera.target=vec3(0,0,1);
		fpsController.angleHor = 0;
		fpsController.angleVert = 0;
		fpsController.update();
	}

	uvec2 windowSize;
	FpsController fpsController;
}