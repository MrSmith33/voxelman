/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
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
const vec4 fogcolor = vec4(0.6, 0.8, 1.0, 1.0);
const float fogdensity = .00001;
void main() {
	float z = gl_FragCoord.z / gl_FragCoord.w;
	float fogModifier = clamp(exp(-fogdensity * z * z), 0.0, 1);
	outputColor = mix(fogcolor, theColor, fogModifier);
}
`;

string color_frag_shader_transparent = `
#version 330
smooth in vec4 theColor;
out vec4 outputColor;
const vec4 fogcolor = vec4(0.6, 0.8, 1.0, 1.0);
const float fogdensity = .00001;
void main() {
	float z = gl_FragCoord.z / gl_FragCoord.w;
	float fogModifier = clamp(exp(-fogdensity * z * z), 0.0, 1);
	outputColor = vec4(mix(fogcolor, theColor, fogModifier).xyz, 0.5);
}
`;

string solid_vert_shader = `
#version 330
layout(location = 0) in vec4 position;
layout(location = 1) in vec4 color;
uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;
smooth out vec4 theColor;
void main() {
	gl_Position = projection * view * model * position;
	theColor = color;
}
`;

string chunk_vert_shader = `
#version 330
layout(location = 0) in vec4 position;
layout(location = 1) in vec4 color;
uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;
smooth out vec4 theColor;
void main() {
	gl_Position = projection * view * model * (position/vec4(7,7,7,1));
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
	ShaderProgram solidShader;
	ShaderProgram transChunkShader;

	IRenderer renderer;
	ConfigOption cameraSensivity;
	ConfigOption cameraFov;

	GLuint projectionLoc = 2; //perspective
	GLuint viewLoc = 3; //camera trandformation
	GLuint modelLoc = 4; //model transformation


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
		chunkShader = renderer.createShaderProgram(chunk_vert_shader, color_frag_shader);
		transChunkShader = renderer.createShaderProgram(chunk_vert_shader, color_frag_shader_transparent);
		solidShader = renderer.createShaderProgram(solid_vert_shader, color_frag_shader);

		chunkShader.bind;
			modelLoc = glGetUniformLocation( solidShader.handle, "model" );//model transformation
			viewLoc = glGetUniformLocation( solidShader.handle, "view" );//camera trandformation
			projectionLoc = glGetUniformLocation( solidShader.handle, "projection" );//perspective

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
		renderer.setClearColor(165,211,238);
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

		draw(debugBatch);
		debugBatch.reset();

		evDispatcher.postEvent(RenderSolid3dEvent(renderer));

		glDisable(GL_DEPTH_TEST);

		renderer.enableAlphaBlending();

		evDispatcher.postEvent(RenderTransparent3dEvent(renderer));

		renderer.enableAlphaBlending();
		evDispatcher.postEvent(Render2Event(renderer));
		evDispatcher.postEvent(Render3Event(renderer));
		renderer.disableAlphaBlending();
		renderer.flush();
	}

	void draw(Batch batch)
	{
		solidShader.bind;
		drawBuffer(batch.triBuffer, GL_TRIANGLES);
		drawBuffer(batch.lineBuffer, GL_LINES);
		drawBuffer(batch.pointBuffer, GL_POINTS);
		solidShader.unbind;
	}

private:

	void drawBuffer(ref ColoredVertex[] buffer, uint mode)
	{
		if (buffer.length == 0) return;

		glUniformMatrix4fv(modelLoc, 1, GL_FALSE, cast(const float*)Matrix4f.identity.arrayof);
		glUniformMatrix4fv(viewLoc, 1, GL_FALSE, camera.cameraMatrix);
		glUniformMatrix4fv(projectionLoc, 1, GL_FALSE, cast(const float*)camera.perspective.arrayof);
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
