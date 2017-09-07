/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.graphics.plugin;

import voxelman.log;
import voxelman.container.buffer;
import voxelman.math;

import pluginlib;
import voxelman.platform.iwindow;
import voxelman.graphics.gl;
import voxelman.graphics.irenderer;
import voxelman.graphics.shaderprogram;
import voxelman.core.config;
import voxelman.core.events;
import voxelman.eventdispatcher.plugin;
import voxelman.gui.plugin;
import voxelman.config.configmanager;
import voxelman.graphics.fpscamera;
public import voxelman.graphics;

import voxelman.graphics.shaders;

final class GraphicsPlugin : IPlugin
{
private:
	uint vao;
	uint vbo;
	EventDispatcherPlugin evDispatcher;
	Matrix4f ortho_projection;

public:
	FpsCamera camera;
	Batch debugBatch;
	Buffer!ColoredVertex transparentBuffer;
	Batch2d overlayBatch;

	SolidShader3d solidShader3d;
	TransparentShader3d transparentShader3d;
	SolidShader2d solidShader2d;

	IRenderer renderer;
	IWindow window;

	ConfigOption cameraSensivity;
	ConfigOption cameraFov;

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
		solidShader3d.compile(renderer);
		transparentShader3d.compile(renderer);
		solidShader2d.compile(renderer);

		ortho_projection.arrayof =
		[
			 2f/1, 0f,   0f, 0f,
			 0f,  -2f/1, 0f, 0f,
			 0f,   0f,  -1f, 0f,
			-1f,   1f,   0f, 1f,
		];
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
		checkgl!glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT);
		renderer.depthTest(true);

		draw(debugBatch);
		debugBatch.reset();

		evDispatcher.postEvent(RenderSolid3dEvent(renderer));

		renderer.depthTest(false);
		renderer.alphaBlending(true);

		evDispatcher.postEvent(RenderTransparent3dEvent(renderer));

		transparentShader3d.bind;
		transparentShader3d.setMVP(Matrix4f.identity, camera.cameraMatrix, camera.perspective);
		transparentShader3d.setTransparency(0.3f);

		drawBuffer(transparentBuffer.data, GL_TRIANGLES);
		transparentShader3d.unbind;
		transparentBuffer.clear();

		evDispatcher.postEvent(Render2Event(renderer));

		draw(overlayBatch);
		overlayBatch.reset();

		evDispatcher.postEvent(Render3Event(renderer));

		renderer.alphaBlending(false);
		renderer.flush();
	}

	void draw(Batch batch)
	{
		solidShader3d.bind;
		solidShader3d.setMVP(Matrix4f.identity, camera.cameraMatrix, camera.perspective);

		drawBuffer(batch.triBuffer.data, GL_TRIANGLES);
		drawBuffer(batch.lineBuffer.data, GL_LINES);
		drawBuffer(batch.pointBuffer.data, GL_POINTS);

		solidShader3d.unbind;
	}

	void draw(Batch2d batch)
	{
		solidShader2d.bind;
		solidShader2d.setProjection(ortho_projection);

		drawBuffer(batch.triBuffer.data, GL_TRIANGLES);
		drawBuffer(batch.lineBuffer.data, GL_LINES);
		drawBuffer(batch.pointBuffer.data, GL_POINTS);

		solidShader2d.unbind;
	}

	void drawBuffer3d(VertexType)(VertexType[] buffer, uint mode)
	{
		if (buffer.length == 0) return;
		solidShader3d.bind;
		solidShader3d.setMVP(Matrix4f.identity, camera.cameraMatrix, camera.perspective);

		drawBuffer(buffer, mode);

		solidShader3d.unbind;
	}

private:

	void updateOrtoMatrix()
	{
		renderer.setViewport(ivec2(0, 0), renderer.framebufferSize);
		ortho_projection.a11 =  2f/renderer.framebufferSize.x;
		ortho_projection.a22 = -2f/renderer.framebufferSize.y;
	}

	void drawBuffer(VertexType)(VertexType[] buffer, uint mode)
	{
		if (buffer.length == 0) return;
		checkgl!glBindVertexArray(vao);
		checkgl!glBindBuffer(GL_ARRAY_BUFFER, vbo);
		checkgl!glBufferData(GL_ARRAY_BUFFER, buffer.length*VertexType.sizeof, buffer.ptr, GL_DYNAMIC_DRAW);
		VertexType.setAttributes();
		checkgl!glBindBuffer(GL_ARRAY_BUFFER, 0);
		checkgl!glDrawArrays(mode, 0, cast(uint)(buffer.length));
		checkgl!glBindVertexArray(0);
	}
}
