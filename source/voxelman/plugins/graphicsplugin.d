/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.plugins.graphicsplugin;

import anchovy.gui;
import dlib.math.vector : uvec2;
import dlib.math.matrix;

import plugin;
import voxelman.plugins.eventdispatcherplugin : GameEvent;
import voxelman.config;
import voxelman.utils.fpscontroller;
import voxelman.utils.camera;

class Draw1Event : GameEvent {
	this(IRenderer renderer)
	{
		this.renderer = renderer;
	}
	IRenderer renderer;
}
class Draw2Event : GameEvent {
	this(IRenderer renderer)
	{
		this.renderer = renderer;
	}
	IRenderer renderer;
}

final class GraphicsPlugin : IPlugin
{
	override string name() @property { return "GraphicsPlugin"; }
	override string semver() @property { return "0.3.0"; }
	override void preInit()
	{
		fpsController.move(START_POS);
		fpsController.camera.sensivity = CAMERA_SENSIVITY;

		fpsController.camera.aspect = cast(float)windowSize.x/windowSize.y;
		fpsController.camera.updateProjection();

		// Setup shaders

		string vShader = cast(string)read("perspective.vert");
		string fShader = cast(string)read("colored.frag");
		chunkShader = new ShaderProgram(vShader, fShader);

		if(!chunkShader.compile())
		{
			writeln(chunkShader.errorLog);
		}
		else
		{
			writeln("Shaders compiled successfully");
		}

		chunkShader.bind;
			modelLoc = glGetUniformLocation( chunkShader.program, "model" );//model transformation
			viewLoc = glGetUniformLocation( chunkShader.program, "view" );//camera trandformation
			projectionLoc = glGetUniformLocation( chunkShader.program, "projection" );//perspective	

			glUniformMatrix4fv(modelLoc, 1, GL_FALSE,
				cast(const float*)Matrix4f.identity.arrayof);
			glUniformMatrix4fv(viewLoc, 1, GL_FALSE,
				cast(const float*)fpsController.cameraMatrix);
			glUniformMatrix4fv(projectionLoc, 1, GL_FALSE,
				cast(const float*)fpsController.camera.perspective.arrayof);
		chunkShader.unbind;
	}

	override void init(IPluginManager pluginman) { }

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

	ShaderProgram chunkShader;
	GLuint modelLoc, viewLoc, projectionLoc;
}