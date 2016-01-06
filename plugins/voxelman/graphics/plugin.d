/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.graphics.plugin;

import std.experimental.logger;
import derelict.opengl3.gl3;
import dlib.math.vector;
import dlib.math.matrix;

import pluginlib;
import anchovy.irenderer;
import anchovy.shaderprogram;
import voxelman.core.config;
import voxelman.core.events;
import voxelman.eventdispatcher.plugin;
import voxelman.gui.plugin;
import voxelman.config.configmanager;
import voxelman.utils.fpscamera;
public import voxelman.utils.renderutils;


shared static this()
{
	pluginRegistry.regClientPlugin(new GraphicsPlugin);
}

string color_frag_shader = `
#version 330
smooth in vec4 theColor;
out vec4 outputColor;
void main() { outputColor = theColor; }
`;

string perspective_vert_shader = `
#version 330
layout(location = 0) in vec4 position;
layout(location = 1) in vec4 color;
smooth out vec4 theColor;
uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;
void main() {
	gl_Position = projection * view * model * position;
	theColor = color;
}
`;

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


	mixin IdAndSemverFrom!(voxelman.graphics.plugininfo);

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto config = resmanRegistry.getResourceManager!ConfigManager;
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
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		auto gui = pluginman.getPlugin!GuiPlugin;

		evDispatcher.subscribeToEvent(&onWindowResizedEvent);
		evDispatcher.subscribeToEvent(&draw);

		renderer = gui.renderer;

		glGenVertexArrays(1, &vao);
		glGenBuffers( 1, &vbo);

		// Setup shaders
		chunkShader = renderer.createShaderProgram(perspective_vert_shader, color_frag_shader);

		chunkShader.bind;
			modelLoc = glGetUniformLocation( chunkShader.handle, "model" );//model transformation
			viewLoc = glGetUniformLocation( chunkShader.handle, "view" );//camera trandformation
			projectionLoc = glGetUniformLocation( chunkShader.handle, "projection" );//perspective

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
		renderer.setClearColor(115,200,169);
		camera.aspect = cast(float)renderer.framebufferSize.x/renderer.framebufferSize.y;
	}

	private void onWindowResizedEvent(ref WindowResizedEvent event)
	{
		camera.aspect = cast(float)event.newSize.x/event.newSize.y;
	}

	void resetCamera()
	{
		camera.position = vec3(0,0,0);
		camera.target = vec3(0,0,1);
		camera.heading = vec2(0, 0);
		camera.update();
	}

	private void draw(ref RenderEvent event)
	{
		glScissor(0, 0, renderer.framebufferSize.x, renderer.framebufferSize.y);
		glViewport(0, 0, renderer.framebufferSize.x, renderer.framebufferSize.y);
		glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT);
		glEnable(GL_DEPTH_TEST);

		evDispatcher.postEvent(Render1Event(renderer));

		chunkShader.bind;
		draw(debugBatch);
		debugBatch.reset();
		chunkShader.unbind;

		glDisable(GL_DEPTH_TEST);

		renderer.enableAlphaBlending();
		evDispatcher.postEvent(Render2Event(renderer));
		evDispatcher.postEvent(Render3Event(renderer));
		renderer.disableAlphaBlending();
		{
			Zone subZone = Zone(event.profiler, "renderer.flush()");
			renderer.flush();
		}
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
