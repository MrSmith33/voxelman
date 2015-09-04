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
import resource;
import voxelman.config;
import voxelman.events;
import voxelman.plugins.eventdispatcherplugin;
import voxelman.plugins.guiplugin;
import voxelman.resourcemanagers.config;
import voxelman.utils.fpscamera;
public import voxelman.utils.renderutils;


final class GraphicsPlugin : IPlugin
{
private:
	uint vao;
	uint vbo;
	EventDispatcherPlugin evDispatcher;

public:
	FpsCamera camera;
	Batch debugBatch;

	ShaderProgram chunkShader;
	GLuint modelLoc, viewLoc, projectionLoc;

	IRenderer renderer;
	ConfigOption cameraSensivity;
	ConfigOption cameraFov;


	override string name() @property { return "GraphicsPlugin"; }
	override string semver() @property { return "0.5.0"; }

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto config = resmanRegistry.getResourceManager!Config;
		cameraSensivity = config.registerOption!float("camera_sensivity", 0.4);
		cameraFov = config.registerOption!float("camera_fov", 60.0);
	}

	override void preInit()
	{
		camera.move(START_POS);
		camera.sensivity = cameraSensivity.get!float;
		camera.fov = cameraFov.get!float;
	}

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin(this);
		evDispatcher.subscribeToEvent(&onWindowResizedEvent);
		evDispatcher.subscribeToEvent(&draw);

		auto gui = pluginman.getPlugin!GuiPlugin(this);
		renderer = gui.renderer;

		glGenVertexArrays(1, &vao);
		glGenBuffers( 1, &vbo);

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
	}

	override void postInit()
	{
		renderer.setClearColor(Color(115,200,169));
		camera.aspect = cast(float)renderer.windowSize.x/renderer.windowSize.y;
	}

	private void onWindowResizedEvent(WindowResizedEvent event)
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

	private void draw(RenderEvent event)
	{
		glScissor(0, 0, renderer.windowSize.x, renderer.windowSize.y);
		glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT);
		glEnable(GL_DEPTH_TEST);

		evDispatcher.postEvent(new Render1Event(renderer));

		chunkShader.bind;
		draw(debugBatch);
		debugBatch.reset();
		chunkShader.unbind;

		glDisable(GL_DEPTH_TEST);

		renderer.enableAlphaBlending();
		evDispatcher.postEvent(new Render2Event(renderer));
		evDispatcher.postEvent(new Render3Event(renderer));
		renderer.disableAlphaBlending();

		renderer.flush();
	}

	void draw(Batch batch)
	{
		drawBuffer(batch.triBuffer, GL_TRIANGLES);
		drawBuffer(batch.lineBuffer, GL_LINES);
		drawBuffer(batch.pointBuffer, GL_POINTS);
	}

private:

	void drawBuffer(ref ColoredVertex[] buffer, uint mode)
	{
		if (buffer.length == 0) return;

		glBindVertexArray(vao);
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glBufferData(GL_ARRAY_BUFFER, buffer.length*ColoredVertex.sizeof, buffer.ptr, GL_DYNAMIC_DRAW);
		glEnableVertexAttribArray(0);
		glEnableVertexAttribArray(1);
		// positions
		glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, ColoredVertex.sizeof, null);
		// color
		glVertexAttribPointer(1, 3, GL_UNSIGNED_BYTE, GL_TRUE, ColoredVertex.sizeof, cast(void*)(12));
		glBindBuffer(GL_ARRAY_BUFFER, 0);

		glDrawArrays(mode, 0, cast(uint)(buffer.length));

		glBindVertexArray(0);
	}
}
