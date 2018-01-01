/**
Copyright: Copyright (c) 2015-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.graphics.plugin;

import pluginlib;
import voxelman.container.buffer;
import voxelman.globalconfig;
import voxelman.log;
import voxelman.math;
public import voxelman.graphics;
import voxelman.gui;
public import voxelman.text.linebuffer;

import voxelman.config.configmanager;
import voxelman.core.config;
import voxelman.core.events;
import voxelman.eventdispatcher.plugin;
import voxelman.gui.plugin;
import voxelman.platform.iwindow;
import voxelman.platform.glfwwindow;
import voxelman.input.keybindingmanager;


class GraphicsResources : IResourceManager
{
	override string id() @property { return "voxelman.graphics.graphicsresources"; }

	GuiContext guictx;
}

final class GraphicsPlugin : IPlugin
{
private:
	uint vao;
	uint vbo;
	EventDispatcherPlugin evDispatcher;
	Matrix4f ortho_projection;
	GraphicsResources graphicsRes;
	GuiContext guictx;

public:
	IWindow window;
	IRenderer renderer;
	ResourceManager resourceManager;
	RenderQueue renderQueue;
	LineBuffer debugText;
	bool showDebugInfo;

	FpsCamera camera;
	Batch debugBatch;
	Buffer!ColoredVertex transparentBuffer;
	Batch2d overlayBatch;

	SolidShader3d solidShader3d;
	TransparentShader3d transparentShader3d;
	SolidShader2d solidShader2d;

	ConfigOption cameraSensivity;
	ConfigOption cameraFov;
	ConfigOption resolution;
	ConfigOption vsync;

	mixin IdAndSemverFrom!"voxelman.graphics.plugininfo";

	override void registerResourceManagers(void delegate(IResourceManager) registerResourceManager)
	{
		guictx = new GuiContext(&debugText);

		resourceManager = new ResourceManager(BUILD_TO_ROOT_PATH~"res");

		graphicsRes = new GraphicsResources;
		graphicsRes.guictx = guictx;

		registerResourceManager(graphicsRes);

		guictx.style.iconMap = resourceManager.loadNamedSpriteSheet("icons", resourceManager.texAtlas, ivec2(16, 16));
		guictx.style.iconPlaceholder = guictx.style.iconMap["no-icon"];
	}

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto keyBindingMan = resmanRegistry.getResourceManager!KeyBindingManager;
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_F8, "key.showDebug", null, (s){showDebugInfo.toggle_bool;}));

		auto config = resmanRegistry.getResourceManager!ConfigManager;
		cameraSensivity = config.registerOption!double("camera_sensivity", 0.4);
		cameraFov = config.registerOption!double("camera_fov", 60.0);
		resolution = config.registerOption!(int[])("resolution", [1280, 720]);
		vsync = config.registerOption!bool("vsync", true);
	}

	override void preInit()
	{
		import voxelman.graphics.gl;

		loadOpenGL();

		window = new GlfwWindow();
		window.init(ivec2(resolution.get!(int[])), "Voxelman client");
		window.setVsync(vsync.get!bool);

		reloadOpenGL();

		// Bind events
		window.windowResized.connect(&windowResized);
		window.closePressed.connect(&closePressed);

		window.mousePressed.connect(&guictx.pointerPressed);
		window.mouseReleased.connect(&guictx.pointerReleased);
		window.mouseMoved.connect(&guictx.pointerMoved);
		window.wheelScrolled.connect(&guictx.onScroll);
		window.keyPressed.connect(&guictx.onKeyPress);
		window.keyReleased.connect(&guictx.onKeyRelease);
		window.charEntered.connect(&guictx.onCharEnter);
		guictx.state.setClipboard = &window.clipboardString;
		guictx.state.getClipboard = &window.clipboardString;

		renderer = new OglRenderer(window);
		renderQueue = new RenderQueue(resourceManager, renderer);

		guictx.pointerMoved(window.mousePosition);
		guictx.style.defaultFont = renderQueue.defaultFont;

		// Camera
		camera.move(vec3(0, 0, 0));
		camera.sensivity = cameraSensivity.get!float;
		camera.fov = cameraFov.get!float;
	}

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		auto gui = pluginman.getPlugin!GuiPlugin;

		// events
		evDispatcher.subscribeToEvent(&onPreUpdateEvent);
		evDispatcher.subscribeToEvent(&onUpdateEvent);
		evDispatcher.subscribeToEvent(&onPostUpdateEvent);
		evDispatcher.subscribeToEvent(&draw);
		evDispatcher.subscribeToEvent(&onGameStopEvent);

		// graphics
		glGenVertexArrays(1, &vao);
		glGenBuffers( 1, &vbo);

		// - Setup shaders
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
		renderQueue.reuploadTexture();
		renderer.setClearColor(165,211,238);
		camera.aspect = cast(float)renderer.framebufferSize.x/renderer.framebufferSize.y;
		updateOrtoMatrix();
	}

	private void windowResized(ivec2 newSize)
	{
		camera.aspect = cast(float)newSize.x/newSize.y;
		updateOrtoMatrix();
		evDispatcher.postEvent(WindowResizedEvent(newSize));
	}

	private void closePressed()
	{
		evDispatcher.postEvent(ClosePressedEvent());
	}

	private void onGameStopEvent(ref GameStopEvent stopEvent)
	{
		window.releaseWindow;
	}

	void resetCamera()
	{
		camera.position = vec3(0,0,0);
		camera.target = vec3(0,0,1);
		camera.heading = vec2(0, 0);
		camera.update();
	}

	private void onPreUpdateEvent(ref PreUpdateEvent event)
	{
		window.processEvents();
		renderQueue.beginFrame();
	}

	private void onUpdateEvent(ref UpdateEvent event)
	{
		guictx.state.canvasSize = renderer.framebufferSize;
		guictx.update(event.deltaTime, renderQueue);
		window.setCursorIcon(guictx.state.cursorIcon);
	}

	private void onPostUpdateEvent(ref PostUpdateEvent event)
	{
		//if (showDebugInfo)
			drawDebugText();
		debugText.clear();
		renderQueue.endFrame();
	}

	private void draw(ref RenderEvent event)
	{
		checkgl!glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT);
		renderer.depthTest(true);

		// 3d solid
		evDispatcher.postEvent(RenderSolid3dEvent(renderer));

		// 3d transparent
		renderer.depthTest(false);
		renderer.alphaBlending(true);

		evDispatcher.postEvent(RenderTransparent3dEvent(renderer));

		// debug drawings
		transparentShader3d.bind;
		transparentShader3d.setMVP(Matrix4f.identity, camera.cameraMatrix, camera.perspective);
		transparentShader3d.setTransparency(0.3f);

		drawBuffer(transparentBuffer.data, GL_TRIANGLES);
		transparentShader3d.unbind;
		transparentBuffer.clear();

		draw(debugBatch);
		debugBatch.reset();

		evDispatcher.postEvent(Render2Event(renderer));

		draw(overlayBatch);
		overlayBatch.reset();

		renderer.depthTest(true);
		//checkgl!glClear(GL_DEPTH_BUFFER_BIT);
		renderQueue.drawFrame();

		evDispatcher.postEvent(Render3Event(renderer));

		renderer.alphaBlending(false);
		renderer.flush();
	}

	int overlayDepth = 1000;
	void drawDebugText()
	{
		auto pos = vec2(renderer.framebufferSize.x, 0);

		auto mesherParams = renderQueue.startTextAt(pos + vec2(-5,5));
		mesherParams.depth = overlayDepth;
		mesherParams.color = cast(Color4ub)Colors.white;

		//info(debugText.lines.data);
		mesherParams.meshText(debugText.lines.data);
		mesherParams.alignMeshedText(Alignment.max);
	}

	void draw(Batch batch, Matrix4f modelMatrix = Matrix4f.identity)
	{
		solidShader3d.bind;
		solidShader3d.setMVP(modelMatrix, camera.cameraMatrix, camera.perspective);

		drawBuffer(batch.triBuffer.data, GL_TRIANGLES);
		drawBuffer(batch.lineBuffer.data, GL_LINES);
		drawBuffer(batch.pointBuffer.data, GL_POINTS);

		solidShader3d.unbind;
	}

	void draw(ref Armature armature, Matrix4f modelMatrix = Matrix4f.identity)
	{
		solidShader3d.bind;
		solidShader3d.setMVP(modelMatrix, camera.cameraMatrix, camera.perspective);

		drawBone(armature.root, modelMatrix);

		solidShader3d.unbind;
	}

	private void drawBone(ref Armature.Bone bone, Matrix4f model)
	{
		model = model * bone.transform;
		solidShader3d.setModel(model);

		drawBuffer(bone.mesh.triBuffer.data, GL_TRIANGLES);
		drawBuffer(bone.mesh.lineBuffer.data, GL_LINES);
		drawBuffer(bone.mesh.pointBuffer.data, GL_POINTS);

		foreach (child; bone.children.data)
			drawBone(child, model);
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
