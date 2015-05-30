/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.plugins.graphicsplugin;

import std.experimental.logger;
import anchovy.gui;
import dlib.math.vector : uvec2;
import dlib.math.matrix;

import plugin;
import voxelman.config;
import voxelman.events;
import voxelman.plugins.eventdispatcherplugin;
import voxelman.plugins.guiplugin;
import voxelman.utils.fpscamera;
public import voxelman.utils.debugdraw;


final class GraphicsPlugin : IPlugin
{
	FpsCamera camera;
	DebugDraw debugDraw;

	ShaderProgram chunkShader;
	GLuint modelLoc, viewLoc, projectionLoc;

	IRenderer renderer;
	EventDispatcherPlugin evDispatcher;
	ConfigOption cameraSensivity;


	override string name() @property { return "GraphicsPlugin"; }
	override string semver() @property { return "0.5.0"; }

	override void loadConfig(Config config)
	{
		cameraSensivity = config.registerOption!float("camera_sensivity", 0.4);
	}

	override void preInit()
	{
		camera.move(START_POS);
		camera.sensivity = cameraSensivity.get!float;

		// Setup shaders

		string vShader = cast(string)read("perspective.vert");
		string fShader = cast(string)read("colored.frag");
		chunkShader = new ShaderProgram(vShader, fShader);

		if(!chunkShader.compile())
		{
			error(chunkShader.errorLog);
		}
		else
		{
			info("Shaders compiled successfully");
		}

		chunkShader.bind;
			modelLoc = glGetUniformLocation( chunkShader.program, "model" );//model transformation
			viewLoc = glGetUniformLocation( chunkShader.program, "view" );//camera trandformation
			projectionLoc = glGetUniformLocation( chunkShader.program, "projection" );//perspective

			glUniformMatrix4fv(modelLoc, 1, GL_FALSE,
				cast(const float*)Matrix4f.identity.arrayof);
			glUniformMatrix4fv(viewLoc, 1, GL_FALSE,
				cast(const float*)camera.cameraMatrix);
			glUniformMatrix4fv(projectionLoc, 1, GL_FALSE,
				cast(const float*)camera.perspective.arrayof);
		chunkShader.unbind;

		debugDraw.init();
	}

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin(this);
		evDispatcher.subscribeToEvent(&onWindowResizedEvent);

		auto gui = pluginman.getPlugin!GuiPlugin(this);
		renderer = gui.renderer;
	}

	override void postInit()
	{
		renderer.setClearColor(Color(115,200,169));
		camera.aspect = cast(float)renderer.windowSize.x/renderer.windowSize.y;
	}

	void onWindowResizedEvent(WindowResizedEvent event)
	{
		camera.aspect = cast(float)event.newSize.x/event.newSize.y;
	}

	void resetCamera()
	{
		camera.position=vec3(0,0,0);
		camera.target=vec3(0,0,1);
		camera.heading = vec2(0, 0);
		camera.update();
	}

	void draw()
	{
		glScissor(0, 0, renderer.windowSize.x, renderer.windowSize.y);
		glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT);

		evDispatcher.postEvent(new Draw1Event(renderer));

		renderer.enableAlphaBlending();
		evDispatcher.postEvent(new Draw2Event(renderer));
		renderer.disableAlphaBlending();

		renderer.flush();
	}
}
