/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module gui;

import std.algorithm;
import std.array;
import std.experimental.logger;
import std.format;
import std.process;
import std.range;
import std.stdio;
import std.string : format;

import derelict.glfw3.glfw3;
import derelict.imgui.imgui;
import derelict.opengl3.gl3;
import imgui_glfw;

import launcher;


struct ItemList(T)
{
	T[]* items;
	size_t currentItem;
	bool hasSelected() @property {
		return currentItem < (*items).length;
	}
	T selected() @property {
		if (currentItem < (*items).length)
			return (*items)[currentItem];
		else if ((*items).length > 0)
			return (*items)[$-1];
		else
			return T.init;
	}

	void update() {
		if (currentItem >= (*items).length)
			currentItem = (*items).length-1;
		if ((*items).length == 0)
			currentItem = 0;
	}
}

struct LauncherGui
{
	bool show_test_window = true;
	bool show_another_window = false;
	float[3] clear_color = [0.3f, 0.4f, 0.6f];
	bool isRunning = true;
	GLFWwindow* window;

	Launcher launcher;

	string pluginFolder = `./plugins`;
	string pluginPackFolder = `./pluginpacks`;
	ItemList!(PluginInfo*) plugins;

	void init()
	{
		class ConciseLogger : FileLogger {
			this(File file, const LogLevel lv = LogLevel.info) @safe {
				super(file, lv);
			}

			override protected void beginLogMsg(string file, int line, string funcName,
				string prettyFuncName, string moduleName, LogLevel logLevel,
				Tid threadId, SysTime timestamp, Logger logger)
				@safe {}
		}
		//auto file = File(filename, "w");
		auto logger = new MultiLogger;
		//logger.insertLogger("fileLogger", new FileLogger(file));
		logger.insertLogger("stdoutLogger", new ConciseLogger(stdout));
		sharedLog = logger;

		playMenu.init(&launcher);
		codeMenu.init(&launcher);
		refresh();

		window = startGlfw("Voxelman launcher", 800, 600);

		if (window is null)
			isRunning = false;

		setStyle();
	}

	void run()
	{
		init();

		if (isRunning)
			glfwShowWindow(window);

		while(isRunning)
		{
			if (glfwWindowShouldClose(window) && !launcher.anyProcessesRunning)
				isRunning = false;
			else
				glfwSetWindowShouldClose(window, false);
			update();
			render();
		}

		close();
	}

	void refresh()
	{
		launcher.clear();
		launcher.setRootPath(pluginFolder, pluginPackFolder);
		launcher.readPlugins();
		launcher.readPluginPacks();
		plugins.items = &launcher.plugins;
		playMenu.refresh();
		codeMenu.refresh();
	}

	void update()
	{
		launcher.update();
		glfwPollEvents();
		igImplGlfwGL3_NewFrame();
		doGui();
		import core.thread;
		Thread.sleep(15.msecs);
	}

	void render()
	{
		ImGuiIO* io = igGetIO();
		glViewport(0, 0, cast(int)io.DisplaySize.x, cast(int)io.DisplaySize.y);
		glClearColor(clear_color[0], clear_color[1], clear_color[2], 0);
		glClear(GL_COLOR_BUFFER_BIT);
		igRender();
		glfwSwapBuffers(window);
	}

	void close()
	{
		igImplGlfwGL3_Shutdown();
		glfwTerminate();
	}

	void doGui()
	{
		//igPushStyleVar(ImGuiStyleVar_FrameRounding, 0f);
		//igGetStyle().FrameRounding = 0.0f;
		igSetNextWindowPos(ImVec2(0,0));
		igSetNextWindowSize(igGetIO().DisplaySize);
		if (igBegin("Main", null, mainWindowFlags))
		{
			drawMainMenu();
			igSameLine();
			drawMenuContent();

			igEnd();
		}
		//igPopStyleVar();
		//igShowTestWindow(null);
	}

	enum SelectedMenu
	{
		play,
		code,
		conf
	}

	SelectedMenu selectedMenu;
	PlayMenu playMenu;
	CodeMenu codeMenu;

	void drawMainMenu()
	{
		igBeginGroup();
		//auto textPtrs = makeFormattedText("%s %s", igGetStyle().FrameRounding, igGetStyle());
		//igTextUnformatted(textPtrs.start, textPtrs.end);
		if (igButton("Play"))
			selectedMenu = SelectedMenu.play;
		if (igButton("Code"))
			selectedMenu = SelectedMenu.code;
		if (igButton("Conf"))
			selectedMenu = SelectedMenu.conf;
		//if (igButton("Refresh"))
		//	refresh();
		igSpacing();
		if (igButton("Exit"))
			isRunning = false;
		igEndGroup();
	}

	void drawMenuContent()
	{
		final switch(selectedMenu) with(SelectedMenu)
		{
			case play:
				playMenu.draw();
				break;
			case code:
				codeMenu.draw();
				break;
			case conf:
				break;
		}
	}
}

struct PlayMenu
{
	enum SelectedMenu
	{
		newGame,
		connect,
		load,
	}
	Launcher* launcher;
	SelectedMenu selectedMenu;
	ItemList!(PluginPack*) pluginPacks;

	void init(Launcher* launcher)
	{
		this.launcher = launcher;
	}

	void refresh()
	{
		pluginPacks.items = &launcher.pluginPacks;
	}

	void draw()
	{
		pluginPacks.update();
		igBeginGroup();

		if (igButton("New"))
			selectedMenu = SelectedMenu.newGame;
		igSameLine();
		if (igButton("Connect"))
			selectedMenu = SelectedMenu.connect;
		igSameLine();
		if (igButton("Load"))
			selectedMenu = SelectedMenu.load;

		//igSeparator();

		if (selectedMenu == SelectedMenu.newGame)
			drawNewGame();

		igEndGroup();
	}

	void drawNewGame()
	{
		string pluginpack = "default";
		if (auto pack = pluginPacks.selected)
			pluginpack = pack.id;

		// ------------------------ PACKAGES -----------------------------------
		igBeginChild("packs", ImVec2(100, -igGetItemsLineHeightWithSpacing()), true);
			foreach(int i, pluginPack; *pluginPacks.items)
			{
				igPushIdInt(cast(int)i);
				immutable bool itemSelected = (i == pluginPacks.currentItem);

				if (igSelectable(pluginPack.id.ptr, itemSelected))
					pluginPacks.currentItem = i;

				igPopId();
			}
		igEndChild();

		igSameLine();

		// ------------------------ PLUGINS ------------------------------------
		if (pluginPacks.hasSelected)
		{
			igBeginChild("pack's plugins", ImVec2(250, -igGetItemsLineHeightWithSpacing()), true);
				foreach(int i, plugin; pluginPacks.selected.plugins)
				{
					igPushIdInt(cast(int)i);
			    	igTextUnformatted(plugin.id.ptr, plugin.id.ptr+plugin.id.length);
		            igPopId();
				}
			igEndChild();
		}

		// ------------------------ BUTTONS ------------------------------------
		igBeginGroup();
			startButtons(launcher, pluginpack);
			igSameLine();
			if (igButton("Stop"))
			{
				size_t numKilled = launcher.stopProcesses();
				launcher.appLog.addLog(format("killed %s processes\n", numKilled));
			}
		igEndGroup();
	}

	void pluginPackPlugins()
	{

	}
}

void startButtons(Launcher* launcher, string pack)
{
	if (igButton("Start client"))
		launcher.compile(CompileParams(AppType.client), StartParams(pack));
	igSameLine();
	if (igButton("Start server"))
		launcher.compile(CompileParams(AppType.server), StartParams(pack));
}

struct CodeMenu
{
	Launcher* launcher;
	ItemList!(PluginPack*) pluginPacks;

	void init(Launcher* launcher)
	{
		this.launcher = launcher;
	}

	void refresh()
	{
		pluginPacks.items = &launcher.pluginPacks;
	}

	bool getItem(int idx, const(char)** out_text)
	{
		*out_text = (*pluginPacks.items)[idx].id.ptr;
		return true;
	}

	void draw()
	{
		igBeginGroup();
		igPushItemWidth(200);
		igCombo3(
			"Pack",
			cast(int*)&pluginPacks.currentItem,
			&getter, &this,
			cast(int)pluginPacks.items.length, -1);
		igSameLine();
		startButtons(launcher, pluginPacks.selected.id);

		foreach(process; launcher.compileJobs) drawJobLog(process);
		foreach(process; launcher.runJobs) drawJobLog(process);

		igEndGroup();
	}

	static extern (C)
	bool getter(void* codeMenu, int idx, const(char)** out_text)
	{
		auto cm = cast(CodeMenu*)codeMenu;
		return cm.getItem(idx, out_text);
	}
}

void drawJobLog(J)(J job)
{
	igPushIdPtr(job);
	if (igCollapsingHeader(job.command.ptr, null, true, true)) {
		if (igButton("Close")) job.needsClose = true;
		igSameLine();
		if (igButton("Clear")) job.log.clear();
        igBeginChildEx(igGetIdPtr(job.command.ptr), ImVec2(0,350), true, ImGuiWindowFlags_HorizontalScrollbar);
		job.log.draw();
        igEndChild();
	}
	igPopId();
}

struct AppLog
{
	import std.array : Appender;
    Appender!(char[]) lines;
    Appender!(size_t[]) lineSizes;
    bool scrollToBottom;

    void clear()
    {
    	lines.clear();
    	lineSizes.clear();
    }

    void addLog(const(char)[] str)
    {
    	import std.regex : ctRegex, splitter;
    	auto splittedLines = splitter(str, ctRegex!"(\r\n|\r|\n|\v|\f)");
    	auto lengths = splittedLines.map!(a => a.length);
    	if (!lineSizes.data.empty)
    	{
    		lineSizes.data[$-1] += lengths.front;
    		lengths.popFront();
    	}
    	lineSizes.put(lengths);
    	foreach(line; splittedLines)
	    	lines.put(line);
        scrollToBottom = true;
    }

    void draw()
    {
        //igSetNextWindowSize(ImVec2(500,400), ImGuiSetCond_FirstUseEver);
        //if (igButton("Clear")) clear();
        //igSeparator();
	    char* lineStart = lines.data.ptr;
	    foreach(lineSize; lineSizes.data)
	    {
	    	igPushTextWrapPos(igGetWindowContentRegionWidth());
	    	igTextUnformatted(lineStart, lineStart+lineSize);
			igPopTextWrapPos();
	    	lineStart += lineSize;
	    }

        if (scrollToBottom)
            igSetScrollHere(1.0f);
        scrollToBottom = false;
    }
}

void setStyle()
{
	ImGuiStyle* style = igGetStyle();
	style.Colors[ImGuiCol_Text]                  = ImVec4(0.00f, 0.00f, 0.00f, 1.00f);
	style.Colors[ImGuiCol_WindowBg]              = ImVec4(1.00f, 1.00f, 1.00f, 1.00f);
	style.Colors[ImGuiCol_Border]                = ImVec4(0.00f, 0.00f, 0.20f, 0.65f);
	style.Colors[ImGuiCol_BorderShadow]          = ImVec4(0.00f, 0.00f, 0.00f, 0.12f);
	style.Colors[ImGuiCol_FrameBg]               = ImVec4(0.80f, 0.80f, 0.80f, 0.39f);
	style.Colors[ImGuiCol_MenuBarBg]             = ImVec4(1.00f, 1.00f, 1.00f, 0.80f);
	style.Colors[ImGuiCol_ScrollbarBg]           = ImVec4(0.47f, 0.47f, 0.47f, 0.00f);
	style.Colors[ImGuiCol_ScrollbarGrab]         = ImVec4(0.55f, 0.55f, 0.55f, 1.00f);
	style.Colors[ImGuiCol_ScrollbarGrabHovered]  = ImVec4(0.55f, 0.55f, 0.55f, 1.00f);
	style.Colors[ImGuiCol_ScrollbarGrabActive]   = ImVec4(0.55f, 0.55f, 0.55f, 1.00f);
	style.Colors[ImGuiCol_ComboBg]               = ImVec4(0.80f, 0.80f, 0.80f, 1.00f);
	style.Colors[ImGuiCol_CheckMark]             = ImVec4(0.36f, 0.40f, 0.71f, 0.60f);
	style.Colors[ImGuiCol_SliderGrab]            = ImVec4(0.52f, 0.56f, 1.00f, 0.60f);
	style.Colors[ImGuiCol_SliderGrabActive]      = ImVec4(0.36f, 0.40f, 0.71f, 0.60f);
	style.Colors[ImGuiCol_Button]                = ImVec4(0.52f, 0.56f, 1.00f, 0.60f);
	style.Colors[ImGuiCol_ButtonHovered]         = ImVec4(0.43f, 0.46f, 0.82f, 0.60f);
	style.Colors[ImGuiCol_ButtonActive]          = ImVec4(0.37f, 0.40f, 0.71f, 0.60f);
	style.Colors[ImGuiCol_TooltipBg]             = ImVec4(0.86f, 0.86f, 0.86f, 0.90f);
	style.Colors[ImGuiCol_ModalWindowDarkening]  = ImVec4(1.00f, 1.00f, 1.00f, 1.00f);
	style.WindowFillAlphaDefault = 1.0f;
}

enum mainWindowFlags = ImGuiWindowFlags_NoTitleBar |
	ImGuiWindowFlags_NoResize |
	ImGuiWindowFlags_NoMove |
	ImGuiWindowFlags_NoCollapse |
	ImGuiWindowFlags_NoSavedSettings;
	//ImGuiWindowFlags_MenuBar;

char[64] buf;
Appender!(char[]) app;

static this()
{
	app = appender(buf[]);
}

static struct TextPtrs {
	char* start;
	char* end;
}

TextPtrs makeFormattedText(Args ...)(string fmt, Args args) {
	app.clear();
	formattedWrite(app, fmt, args);
	return TextPtrs(app.data.ptr, app.data.ptr + app.data.length);
}
