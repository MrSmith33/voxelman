/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.graphics.plugin;

import voxelman.log;
import derelict.opengl3.gl3;
import voxelman.container.buffer;
import voxelman.math;
import dlib.math.matrix;

import pluginlib;
import anchovy.iwindow;
import anchovy.irenderer;
import anchovy.shaderprogram;
import voxelman.core.config;
import voxelman.core.events;
import voxelman.eventdispatcher.plugin;
import voxelman.gui.plugin;
import voxelman.config.configmanager;
import voxelman.utils.fpscamera;
public import voxelman.graphics;


string solid_frag_shader = `
#version 330
smooth in vec4 frag_color;
out vec4 out_color;

void main() {
	out_color = frag_color;
}
`;

string color_frag_shader_transparent = `
#version 330
smooth in vec4 frag_color;
out vec4 out_color;

void main() {
	out_color = vec4(frag_color.xyz, 0.5);
}
`;

string vert_shader_2d = `
#version 330
layout(location = 0) in vec2 position;
layout(location = 1) in vec4 color;

smooth out vec4 frag_color;
uniform mat4 proj_mat;

void main() {
	gl_Position = proj_mat * vec4(position.xy, 0, 1);
	frag_color = color;
}
`;

string solid_vert_shader = `
#version 330
layout(location = 0) in vec4 position;
layout(location = 1) in vec4 color;
uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;
smooth out vec4 frag_color;
void main() {
	gl_Position = projection * view * model * position;
	frag_color = color;
}
`;

string chunk_vert_shader = `
#version 330
layout(location = 0) in vec4 position;
layout(location = 1) in vec4 color;
uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;
smooth out vec4 frag_color;
void main() {
	gl_Position = projection * view * model * (position);
	frag_color = color;
}
`;

final class GraphicsPlugin : IPlugin
{
private:
	uint vao;
	uint vbo;
	EventDispatcherPlugin evDispatcher;
	float[4][4] ortho_projection;

public:
	FpsCamera camera;
	Batch debugBatch;
	Batch2d overlayBatch;

	ShaderProgram chunkShader;
	ShaderProgram solidShader;
	ShaderProgram solidShader2d;
	ShaderProgram transChunkShader;

	IRenderer renderer;
	IWindow window;

	ConfigOption cameraSensivity;
	ConfigOption cameraFov;

	GLint projectionLoc = 2; //perspective
	GLint viewLoc = 3; //camera trandformation
	GLint modelLoc = 4; //model transformation
	GLint projLoc = 5; // 2d projection


	mixin IdAndSemverFrom!"voxelman.graphics.plugininfo";

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto config = resmanRegistry.getResourceManager!ConfigManager;
		cameraSensivity = config.registerOption!double("camera_sensivity", 0.4);
		cameraFov = config.registerOption!double("camera_fov", 60.0);
	}

	override void preInit()
	{
		camera.move(vec3(0, 0, 0));
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
		window = gui.window;

		glGenVertexArrays(1, &vao);
		glGenBuffers( 1, &vbo);

		// Setup shaders
		chunkShader = renderer.createShaderProgram(chunk_vert_shader, solid_frag_shader);
		transChunkShader = renderer.createShaderProgram(chunk_vert_shader, color_frag_shader_transparent);
		solidShader = renderer.createShaderProgram(solid_vert_shader, solid_frag_shader);
		solidShader2d = renderer.createShaderProgram(vert_shader_2d, solid_frag_shader);

		modelLoc = glGetUniformLocation( solidShader.handle, "model" ); // model transformation
		viewLoc = glGetUniformLocation( solidShader.handle, "view" ); // camera trandformation
		projectionLoc = glGetUniformLocation( solidShader.handle, "projection" ); // perspective
		projLoc = glGetUniformLocation( solidShader2d.handle, "proj_mat" ); // 2d projection
	}

	override void postInit()
	{
		renderer.setClearColor(165,211,238);
		camera.aspect = cast(float)renderer.framebufferSize.x/renderer.framebufferSize.y;
		updateOrtoMatrix();
	}

	private void onWindowResizedEvent(ref WindowResizedEvent event)
	{
		camera.aspect = cast(float)event.newSize.x/event.newSize.y;
		updateOrtoMatrix();
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

		draw(overlayBatch);
		overlayBatch.reset();

		evDispatcher.postEvent(Render3Event(renderer));

		renderer.disableAlphaBlending();
		renderer.flush();
	}

	void draw(Batch batch)
	{
		solidShader.bind;

		glUniformMatrix4fv(modelLoc, 1, GL_FALSE, cast(const float*)Matrix4f.identity.arrayof);
		glUniformMatrix4fv(viewLoc, 1, GL_FALSE, camera.cameraMatrix);
		glUniformMatrix4fv(projectionLoc, 1, GL_FALSE, cast(const float*)camera.perspective.arrayof);

		drawBuffer(batch.triBuffer.data, GL_TRIANGLES);
		drawBuffer(batch.lineBuffer.data, GL_LINES);
		drawBuffer(batch.pointBuffer.data, GL_POINTS);

		solidShader.unbind;
	}

	void draw(Batch2d batch)
	{
		solidShader2d.bind;

		glUniformMatrix4fv(projLoc, 1, GL_FALSE, &ortho_projection[0][0]);

		drawBuffer(batch.triBuffer.data, GL_TRIANGLES);
		drawBuffer(batch.lineBuffer.data, GL_LINES);
		drawBuffer(batch.pointBuffer.data, GL_POINTS);

		solidShader2d.unbind;
	}

private:

	void updateOrtoMatrix()
	{
		glViewport(0, 0, renderer.framebufferSize.x,
			renderer.framebufferSize.y);
		auto w = renderer.framebufferSize.x;
		auto h = renderer.framebufferSize.y;
		ortho_projection =
		[
			[ 2f/w, 0f,   0f, 0f ],
			[ 0f,  -2f/h, 0f, 0f ],
			[ 0f,   0f,  -1f, 0f ],
			[-1f,   1f,   0f, 1f ],
		];
	}

	void drawBuffer(VertexType)(VertexType[] buffer, uint mode)
	{
		if (buffer.length == 0) return;
		glBindVertexArray(vao);
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glBufferData(GL_ARRAY_BUFFER, buffer.length*VertexType.sizeof, buffer.ptr, GL_DYNAMIC_DRAW);
		VertexType.setAttributes();
		glBindBuffer(GL_ARRAY_BUFFER, 0);
		glDrawArrays(mode, 0, cast(uint)(buffer.length));
		glBindVertexArray(0);
	}
}
