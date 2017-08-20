/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko, Stephan Dilly (imgui_d_test).
*/
module voxelman.imgui_glfw;

import derelict.imgui.imgui;
import derelict.opengl3.gl3;
import derelict.glfw3.glfw3;
import voxelman.platform.input;
import voxelman.math;

struct ImguiState
{
	GLFWwindow* window;
	double      time = 0.0f;
	bool[7]     mousePressed;
	float       mouseWheel = 0.0f;
	GLuint      fontTexture = 0;
	int         shaderHandle = 0;
	int         vertHandle = 0;
	int         fragHandle = 0;
	int         attribLocationTex = 0;
	int         attribLocationProjMtx = 0;
	int         attribLocationPosition = 0;
	int         attribLocationUV = 0;
	int         attribLocationColor = 0;
	uint        vboHandle;
	uint        vaoHandle;
	uint        elementsHandle;
	ClipboardHelper clipboardHelper;

	void init(GLFWwindow* window, string[] fonts = null)
	{
		this.window = window;
		clipboardHelper.window = window;

		ImGuiIO* io = igGetIO();

		io.KeyMap[ImGuiKey_Tab] = GLFW_KEY_TAB;
		io.KeyMap[ImGuiKey_LeftArrow] = GLFW_KEY_LEFT;
		io.KeyMap[ImGuiKey_RightArrow] = GLFW_KEY_RIGHT;
		io.KeyMap[ImGuiKey_UpArrow] = GLFW_KEY_UP;
		io.KeyMap[ImGuiKey_DownArrow] = GLFW_KEY_DOWN;
		io.KeyMap[ImGuiKey_Home] = GLFW_KEY_HOME;
		io.KeyMap[ImGuiKey_End] = GLFW_KEY_END;
		io.KeyMap[ImGuiKey_Delete] = GLFW_KEY_DELETE;
		io.KeyMap[ImGuiKey_Backspace] = GLFW_KEY_BACKSPACE;
		io.KeyMap[ImGuiKey_Enter] = GLFW_KEY_ENTER;
		io.KeyMap[ImGuiKey_Escape] = GLFW_KEY_ESCAPE;
		io.KeyMap[ImGuiKey_A] = GLFW_KEY_A;
		io.KeyMap[ImGuiKey_C] = GLFW_KEY_C;
		io.KeyMap[ImGuiKey_V] = GLFW_KEY_V;
		io.KeyMap[ImGuiKey_X] = GLFW_KEY_X;
		io.KeyMap[ImGuiKey_Y] = GLFW_KEY_Y;
		io.KeyMap[ImGuiKey_Z] = GLFW_KEY_Z;

		io.SetClipboardTextFn = &clipboardHelper.setClipboardText;
		io.GetClipboardTextFn = &clipboardHelper.getClipboardText;
	}

	void newFrame()
	{
		if (!fontTexture)
			createDeviceObjects();

		auto io = igGetIO();

		// Setup display size (every frame to accommodate for window resizing)
		int w, h;
		int display_w, display_h;
		glfwGetWindowSize(window, &w, &h);
		glfwGetFramebufferSize(window, &display_w, &display_h);
		io.DisplaySize = ImVec2(cast(float)display_w, cast(float)display_h);

		// Setup time step
		double current_time =  glfwGetTime();
		io.DeltaTime = time > 0.0 ? cast(float)(current_time - time) : cast(float)(1.0f/60.0f);
		time = current_time;

		// Setup inputs
		// (we already got mouse wheel, keyboard keys & characters from glfw callbacks polled in glfwPollEvents())
		if (glfwGetWindowAttrib(window, GLFW_FOCUSED))
		{
			double mouse_x, mouse_y;
			glfwGetCursorPos(window, &mouse_x, &mouse_y);
			mouse_x *= cast(float)display_w / w;                        // Convert mouse coordinates to pixels
			mouse_y *= cast(float)display_h / h;
			io.MousePos = ImVec2(mouse_x, mouse_y);   // Mouse position, in pixels (set to -1,-1 if no mouse / on another screen, etc.)

			io.KeyShift = glfwGetKey(window, GLFW_KEY_LSHIFT) || glfwGetKey(window, GLFW_KEY_RSHIFT);
			io.KeyCtrl = glfwGetKey(window, GLFW_KEY_LCTRL) || glfwGetKey(window, GLFW_KEY_RCTRL);
			io.KeyAlt = glfwGetKey(window, GLFW_KEY_LALT) || glfwGetKey(window, GLFW_KEY_RALT);
		}
		else
		{
			io.MousePos = ImVec2(-1,-1);
		}

		for (int i = 0; i < 3; i++)
		{
			io.MouseDown[i] = mousePressed[i] || glfwGetMouseButton(window, i) != 0;    // If a mouse press event came, always pass it as "mouse held this frame", so we don't miss click-release events that are shorter than 1 frame.
			mousePressed[i] = false;
		}

		io.MouseWheel = mouseWheel;
		mouseWheel = 0.0f;

		// Hide/show hardware mouse cursor
		//glfwSetInputMode(window, GLFW_CURSOR, io.MouseDrawCursor ? GLFW_CURSOR_HIDDEN : GLFW_CURSOR_NORMAL);

		igNewFrame();
	}

	bool mouseCaptured() @property
	{
		return igGetIO().WantCaptureMouse;
	}

	bool keyboardCaptured() @property
	{
		return igGetIO().WantCaptureKeyboard || igGetIO().WantTextInput;
	}

	void render()
	{
		igRender();
		renderDrawLists(igGetDrawData());
	}

	void renderDrawLists(ImDrawData* data)
	{
		// Setup render state: alpha-blending enabled, no face culling, no depth testing, scissor enabled
		GLint last_program, last_texture;
		glGetIntegerv(GL_CURRENT_PROGRAM, &last_program);
		glGetIntegerv(GL_TEXTURE_BINDING_2D, &last_texture);
		glEnable(GL_BLEND);
		glBlendEquation(GL_FUNC_ADD);
		glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
		glDisable(GL_CULL_FACE);
		glDisable(GL_DEPTH_TEST);
		glEnable(GL_SCISSOR_TEST);
		glActiveTexture(GL_TEXTURE0);

		auto io = igGetIO();
		// Setup orthographic projection matrix
		const float width = io.DisplaySize.x;
		const float height = io.DisplaySize.y;
		const float[4][4] ortho_projection =
		[
			[ 2.0f/width,	0.0f,			0.0f,		0.0f ],
			[ 0.0f,			2.0f/-height,	0.0f,		0.0f ],
			[ 0.0f,			0.0f,			-1.0f,		0.0f ],
			[ -1.0f,		1.0f,			0.0f,		1.0f ],
		];
		glUseProgram(shaderHandle);
		glUniform1i(attribLocationTex, 0);
		glUniformMatrix4fv(attribLocationProjMtx, 1, GL_FALSE, &ortho_projection[0][0]);

		glBindVertexArray(vaoHandle);
		glBindBuffer(GL_ARRAY_BUFFER, vboHandle);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, elementsHandle);

		foreach (n; 0..data.CmdListsCount)
		{
			ImDrawList* cmd_list = data.CmdLists[n];
			ImDrawIdx* idx_buffer_offset;

			auto countVertices = ImDrawList_GetVertexBufferSize(cmd_list);
			auto countIndices = ImDrawList_GetIndexBufferSize(cmd_list);

			glBufferData(GL_ARRAY_BUFFER, countVertices * ImDrawVert.sizeof, cast(GLvoid*)ImDrawList_GetVertexPtr(cmd_list,0), GL_STREAM_DRAW);
			glBufferData(GL_ELEMENT_ARRAY_BUFFER, countIndices * ImDrawIdx.sizeof, cast(GLvoid*)ImDrawList_GetIndexPtr(cmd_list,0), GL_STREAM_DRAW);

			auto cmdCnt = ImDrawList_GetCmdSize(cmd_list);

			foreach(i; 0..cmdCnt)
			{
				auto pcmd = ImDrawList_GetCmdPtr(cmd_list, i);

				if (pcmd.UserCallback)
				{
					pcmd.UserCallback(cmd_list, pcmd);
				}
				else
				{
					glBindTexture(GL_TEXTURE_2D, cast(GLuint)pcmd.TextureId);
					glScissor(cast(int)pcmd.ClipRect.x, cast(int)(height - pcmd.ClipRect.w), cast(int)(pcmd.ClipRect.z - pcmd.ClipRect.x), cast(int)(pcmd.ClipRect.w - pcmd.ClipRect.y));
					glDrawElements(GL_TRIANGLES, pcmd.ElemCount, GL_UNSIGNED_SHORT, idx_buffer_offset);
				}

				idx_buffer_offset += pcmd.ElemCount;
			}
		}

		// Restore modified state
		glBindVertexArray(0);
		glBindBuffer(GL_ARRAY_BUFFER, 0);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
		glUseProgram(last_program);
		glDisable(GL_SCISSOR_TEST);
		glBindTexture(GL_TEXTURE_2D, last_texture);
	}

	void createDeviceObjects()
	{
		const GLchar* vertex_shader =
			"#version 330\n"~
			"uniform mat4 ProjMtx;\n"~
			"in vec2 Position;\n"~
			"in vec2 UV;\n"~
			"in vec4 Color;\n"~
			"out vec2 Frag_UV;\n"~
			"out vec4 Frag_Color;\n"~
			"void main()\n"~
			"{\n"~
			"	Frag_UV = UV;\n"~
			"	Frag_Color = Color;\n"~
			"	gl_Position = ProjMtx * vec4(Position.xy,0,1);\n"~
			"}\n";

		const GLchar* fragment_shader =
			"#version 330\n"~
			"uniform sampler2D Texture;\n"~
			"in vec2 Frag_UV;\n"~
			"in vec4 Frag_Color;\n"~
			"out vec4 Out_Color;\n"~
			"void main()\n"~
			"{\n"~
			"	Out_Color = Frag_Color * texture( Texture, Frag_UV.st);\n"~
			"}\n";

		shaderHandle = glCreateProgram();
		vertHandle = glCreateShader(GL_VERTEX_SHADER);
		fragHandle = glCreateShader(GL_FRAGMENT_SHADER);
		glShaderSource(vertHandle, 1, &vertex_shader, null);
		glShaderSource(fragHandle, 1, &fragment_shader, null);
		glCompileShader(vertHandle);
		glCompileShader(fragHandle);
		glAttachShader(shaderHandle, vertHandle);
		glAttachShader(shaderHandle, fragHandle);
		glLinkProgram(shaderHandle);

		attribLocationTex = glGetUniformLocation(shaderHandle, "Texture");
		attribLocationProjMtx = glGetUniformLocation(shaderHandle, "ProjMtx");
		attribLocationPosition = glGetAttribLocation(shaderHandle, "Position");
		attribLocationUV = glGetAttribLocation(shaderHandle, "UV");
		attribLocationColor = glGetAttribLocation(shaderHandle, "Color");

		glGenBuffers(1, &vboHandle);
		glGenBuffers(1, &elementsHandle);

		glGenVertexArrays(1, &vaoHandle);
		glBindVertexArray(vaoHandle);
		glBindBuffer(GL_ARRAY_BUFFER, vboHandle);
		glEnableVertexAttribArray(attribLocationPosition);
		glEnableVertexAttribArray(attribLocationUV);
		glEnableVertexAttribArray(attribLocationColor);

		glVertexAttribPointer(attribLocationPosition, 2, GL_FLOAT, GL_FALSE, ImDrawVert.sizeof, cast(void*)0);
		glVertexAttribPointer(attribLocationUV, 2, GL_FLOAT, GL_FALSE, ImDrawVert.sizeof, cast(void*)ImDrawVert.uv.offsetof);
		glVertexAttribPointer(attribLocationColor, 4, GL_UNSIGNED_BYTE, GL_TRUE, ImDrawVert.sizeof, cast(void*)ImDrawVert.col.offsetof);

		glBindVertexArray(0);
		glBindBuffer(GL_ARRAY_BUFFER, 0);

		createFontsTexture();
	}

	void createFontsTexture()
	{
		ImGuiIO* io = igGetIO();

		ubyte* pixels;
		int width, height;
		ImFontAtlas_GetTexDataAsRGBA32(io.Fonts,&pixels,&width,&height,null);

		glGenTextures(1, &fontTexture);
		glBindTexture(GL_TEXTURE_2D, fontTexture);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixels);

		// Store our identifier
		ImFontAtlas_SetTexID(io.Fonts, cast(void*)fontTexture);
	}

	void onMousePressed(PointerButton button, uint modifiers)
	{
		mousePressed[button] = true;
	}

	void onMouseReleased(PointerButton button, uint modifiers)
	{
		mousePressed[button] = false;
	}

	void scrollCallback(dvec2 delta)
	{
		mouseWheel += delta.y;
	}

	void onKeyPressed(KeyCode key, uint modifiers)
	{
		igGetIO().KeysDown[key] = true;
		if (key == KeyCode.KEY_KP_ENTER)
			igGetIO().KeysDown[KeyCode.KEY_ENTER] = true;
	}

	void onKeyReleased(KeyCode key, uint modifiers)
	{
		igGetIO().KeysDown[key] = false;
		if (key == KeyCode.KEY_KP_ENTER)
			igGetIO().KeysDown[KeyCode.KEY_ENTER] = false;
	}

	void charCallback(dchar c)
	{
		if (c > 0 && c < 0x10000)
			ImGuiIO_AddInputCharacter(cast(ushort)c);
	}

	void shutdown()
	{
		if (vaoHandle) glDeleteVertexArrays(1, &vaoHandle);
		if (vboHandle) glDeleteBuffers(1, &vboHandle);
		if (elementsHandle) glDeleteBuffers(1, &elementsHandle);
		vaoHandle = 0;
		vboHandle = 0;
		elementsHandle = 0;

		glDetachShader(shaderHandle, vertHandle);
		glDeleteShader(vertHandle);
		vertHandle = 0;

		glDetachShader(shaderHandle, fragHandle);
		glDeleteShader(fragHandle);
		fragHandle = 0;

		glDeleteProgram(shaderHandle);
		shaderHandle = 0;

		if (fontTexture)
		{
			glDeleteTextures(1, &fontTexture);
			ImFontAtlas_SetTexID(igGetIO().Fonts, cast(void*)0);
			fontTexture = 0;
		}

		igShutdown();
	}
}

GLFWwindow* startGlfw(string windowTitle, int w, int h)
{
	// Setup window
	glfwSetErrorCallback(&error_callback);
	if (!glfwInit())
		return null;
	glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
	glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);
	//glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
	glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, true);
	glfwWindowHint(GLFW_VISIBLE, false);
	auto window = glfwCreateWindow(w, h, windowTitle.ptr, null, null);
	glfwMakeContextCurrent(window);

	DerelictGL3.reload();

	return window;
}

extern(C) nothrow void error_callback(int error, const(char)* description)
{
	import std.stdio;
	import std.conv;
	try writefln("glfw err: %s ('%s')", error, to!string(description));
	catch(Throwable){}
}

struct ClipboardHelper
{
	static GLFWwindow* window;

	static extern(C) nothrow
	const(char)* getClipboardText()
	{
		return glfwGetClipboardString(window);
	}

	static extern(C) nothrow
	void setClipboardText(const(char)* text)
	{
		glfwSetClipboardString(window, text);
	}
}
