/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
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
import std.string : format, fromStringz;
import std.typecons : Flag, Yes, No;

import voxelman.math;
import derelict.glfw3.glfw3;
import derelict.imgui.imgui;
import derelict.opengl3.gl3;
import anchovy.glfwwindow;
import voxelman.imgui_glfw;
import voxelman.utils.libloader;
import voxelman.utils.textformatter;
import voxelman.utils.linebuffer;

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

	ref T opIndex(size_t i) {
		return (*items)[i];
	}
}

struct LauncherGui
{
	bool show_test_window = true;
	bool show_another_window = false;
	float[3] clear_color = [0.3f, 0.4f, 0.6f];
	bool isRunning = true;
	ImguiState igState;
	GlfwWindow window;

	Launcher launcher;

	string pluginFolder = `./plugins`;
	string pluginPackFolder = `./pluginpacks`;
	string toolFolder = `./tools`;
	ItemList!(PluginInfo*) plugins;

	void init()
	{
		import std.datetime : SysTime;
		import std.concurrency : Tid;
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

		launcher.init();

		playMenu.init(&launcher);
		codeMenu.init(&launcher);
		refresh();

		window = new GlfwWindow();
		window.init(ivec2(820, 600), "Voxelman launcher");
		igState.init(window.handle);
		window.keyPressed.connect(&igState.onKeyPressed);
		window.keyReleased.connect(&igState.onKeyReleased);
		window.charEntered.connect(&igState.charCallback);
		window.mousePressed.connect(&igState.onMousePressed);
		window.mouseReleased.connect(&igState.onMouseReleased);
		window.wheelScrolled.connect((dvec2 s) => igState.scrollCallback(s.y));

		if (window is null)
			isRunning = false;

		setStyle();
	}

	void run()
	{
		DerelictGL3.load();
		loadLib(DerelictGLFW3, "", "glfw3");
		loadLib(DerelictImgui, "", "cimgui");

		init();

		while(isRunning)
		{
			if (glfwWindowShouldClose(window.handle) && !launcher.anyProcessesRunning)
				isRunning = false;
			else
				glfwSetWindowShouldClose(window.handle, false);
			update();
			render();
		}

		close();
	}

	void refresh()
	{
		launcher.setRootPath(pluginFolder, pluginPackFolder, toolFolder);
		launcher.refresh();
		plugins.items = &launcher.plugins;
		playMenu.refresh();
		codeMenu.refresh();
	}

	void update()
	{
		launcher.update();
		window.processEvents();
		igState.newFrame();
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
		igState.render();
		glfwSwapBuffers(window.handle);
	}

	void close()
	{
		window.releaseWindow;
		igState.shutdown();
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

		menuEntry("Play", SelectedMenu.play);
		menuEntry("Code", SelectedMenu.code);
		menuEntry("Conf", SelectedMenu.conf);

		//if (igButton("Refresh"))
		//	refresh();
		igSpacing();
		if (igButton("Exit"))
			isRunning = false;
		igEndGroup();
	}

	void menuEntry(string text, SelectedMenu select)
	{
		ImGuiStyle* style = igGetStyle();
		const ImVec4 color       = style.Colors[ImGuiCol_Button];
		const ImVec4 colorActive = style.Colors[ImGuiCol_ButtonActive];
		const ImVec4 colorHover  = style.Colors[ImGuiCol_ButtonHovered];

		if (selectedMenu == select)
		{
			style.Colors[ImGuiCol_Button]        = colorActive;
			style.Colors[ImGuiCol_ButtonActive]  = colorActive;
			style.Colors[ImGuiCol_ButtonHovered] = colorActive;
		}
		else
		{
			style.Colors[ImGuiCol_Button]        = color;
			style.Colors[ImGuiCol_ButtonActive]  = colorActive;
			style.Colors[ImGuiCol_ButtonHovered] = colorHover;
		}

		if (igButton(text.ptr)) selectedMenu = select;

		style.Colors[ImGuiCol_Button] =         color;
		style.Colors[ImGuiCol_ButtonActive] =   colorActive;
		style.Colors[ImGuiCol_ButtonHovered] =  colorHover;
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
		worlds,
		connect,
		newGame,
	}
	Launcher* launcher;
	SelectedMenu selectedMenu;
	ItemList!(PluginPack*) pluginPacks;
	ItemList!(ServerInfo*) servers;
	ItemList!(SaveInfo*) saves;
	AddServerDialog addServerDlg;
	NewSaveDialog newSaveDlg;

	void init(Launcher* launcher)
	{
		this.launcher = launcher;
		addServerDlg.launcher = launcher;
		newSaveDlg.launcher = launcher;
	}

	void refresh()
	{
		pluginPacks.items = &launcher.pluginPacks;
		servers.items = &launcher.servers;
		saves.items = &launcher.saves;
	}

	void draw()
	{
		pluginPacks.update();
		servers.update();
		saves.update();
		igBeginGroup();

		if (igButton("Worlds##Play"))
			selectedMenu = SelectedMenu.worlds;
		igSameLine();
		if (igButton("Connect##Play"))
			selectedMenu = SelectedMenu.connect;
		//if (igButton("New##Play"))
		//	selectedMenu = SelectedMenu.newGame;
		//igSameLine();

		final switch(selectedMenu)
		{
			case SelectedMenu.worlds:
				drawWorlds(); break;
			case SelectedMenu.connect:
				drawConnect(); break;
			case SelectedMenu.newGame:
				drawNewGame(); break;
		}

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
			igBeginChild("pack's plugins", ImVec2(220, -igGetItemsLineHeightWithSpacing()), true);
				foreach(int i, plugin; pluginPacks.selected.plugins)
				{
					igPushIdInt(cast(int)i);
					igTextUnformatted(plugin.id.ptr, plugin.id.ptr+plugin.id.length);
					igPopId();
				}
			igEndChild();
		}
	}

	void drawConnect()
	{
		igBeginChild("Servers", ImVec2(400, -igGetItemsLineHeightWithSpacing()), true);
			foreach(int i, server; *servers.items)
			{
				igPushIdInt(cast(int)i);
				immutable bool itemSelected = (i == servers.currentItem);

				if (igSelectable(server.name.ptr, itemSelected))
					servers.currentItem = i;
				igPopId();
			}
		igEndChild();

		if (addServerDlg.show())
		{
			refresh();
		}

		if (servers.hasSelected)
		{
			igSameLine();
			if (igButton("Remove##Servers"))
				launcher.removeServer(servers.currentItem);
			igSameLine();
			if (igButton("Connect"))
			{
				launcher.connect(servers.selected, pluginPacks.selected);
			}
		}
	}

	void drawWorlds()
	{
		enum tableWidth = 300;
		igBeginChild("Saves", ImVec2(tableWidth, -igGetItemsLineHeightWithSpacing()), true);
		igColumns(2);
		igSetColumnOffset(1, tableWidth - 90);
			foreach(int i, save; *saves.items)
			{
				igPushIdInt(cast(int)i);
				immutable bool itemSelected = (i == saves.currentItem);

				if (igSelectable(save.name.ptr, itemSelected, ImGuiSelectableFlags_SpanAllColumns))
					saves.currentItem = i;
				igNextColumn();
				igTextUnformatted(save.displaySize.ptr, save.displaySize.ptr+save.displaySize.length);
				igNextColumn();
				igPopId();
			}
		igColumns(1);
		igEndChild();

		size_t newSaveIndex;
		if (newSaveDlg.show(newSaveIndex)) {
			refresh();
			saves.currentItem = newSaveIndex;
		}
		igSameLine();

		if (saves.hasSelected)
		{
			if (igButton("Delete##Saves"))
				igOpenPopup("Confirm");
			if (igBeginPopupModal("Confirm", null, ImGuiWindowFlags_AlwaysAutoResize))
			{
				if (igButton("Delete##Confirm"))
				{
					launcher.deleteSave(saves.currentItem);
					refresh();
					igCloseCurrentPopup();
				}
				igSameLine();
				if (igButton("Cancel##Confirm"))
					igCloseCurrentPopup();
				igEndPopup();
			}
		}

		igSameLine();
		if (igButton("Refresh##Saves")) {
			launcher.refreshSaves();
			refresh();
		}

		if (saves.hasSelected)
		{
			igSameLine();
			igSetCursorPosX(tableWidth - 50);
			if (igButton("Server##Saves"))
			{
				launcher.startServer(pluginPacks.selected, saves.selected);
			}
			igSameLine();
			igSetCursorPosX(tableWidth + 10);
			if (igButton("Start##Saves"))
			{
				launcher.startCombined(pluginPacks.selected, saves.selected);
			}
		}
	}
}

struct NewSaveDialog
{
	char[128] saveInputBuffer;
	Launcher* launcher;

	bool show(out size_t newSaveIndex)
	{
		bool result;
		if (igButton("New"))
			igOpenPopup("New world");
		if (igBeginPopupModal("New world", null, ImGuiWindowFlags_AlwaysAutoResize))
		{
			bool entered;
			if (igInputText("World name", saveInputBuffer.ptr, saveInputBuffer.length, ImGuiInputTextFlags_EnterReturnsTrue))
			{
				entered = true;
			}

			if (igButton("Create") || entered)
			{
				newSaveIndex = launcher.createSave(saveInputBuffer.fromCString);
				resetFields();

				igCloseCurrentPopup();
				result = true;
			}
			igSameLine();
			if (igButton("Cancel"))
				igCloseCurrentPopup();

			igEndPopup();
		}
		return result;
	}

	void resetFields()
	{
		saveInputBuffer[] = '\0';
	}
}

struct AddServerDialog
{
	char[128] serverInputBuffer;
	char[16] ipAddress;
	int port = DEFAULT_PORT;
	Launcher* launcher;

	bool show()
	{
		if (igButton("Add"))
			igOpenPopup("add");
		if (igBeginPopupModal("add", null, ImGuiWindowFlags_AlwaysAutoResize))
		{
			igInputText("Server name", serverInputBuffer.ptr, serverInputBuffer.length);
			igInputText("IP/port", ipAddress.ptr, ipAddress.length, ImGuiInputTextFlags_CharsDecimal);
			igSameLine();
			igInputInt("##port", &port);
			port = clamp(port, 0, ushort.max);

			if (igButton("Add"))
			{
				launcher.addServer(ServerInfo(
					serverInputBuffer.fromCString(),
					ipAddress.fromCString(),
					cast(ushort)port));
				resetFields();

				igCloseCurrentPopup();
				return true;
			}
			igSameLine();
			if (igButton("Cancel"))
				igCloseCurrentPopup();

			igEndPopup();
		}
		return false;
	}

	void resetFields()
	{
		Launcher* l = launcher;
		this = AddServerDialog();
		launcher = l;
	}
}

import std.traits : Parameters;
auto withWidth(float width, alias func)(auto ref Parameters!func args)
{
	scope(exit) igPopItemWidth();
	igPushItemWidth(width);
	return func(args);
}

extern (C)
bool itemGetter(T)(void* itemList, int idx, const(char)** out_text)
{
	auto il = cast(T*)itemList;
	*out_text = (*il.items)[idx].guiName.ptr;
	return true;
}

struct CodeMenu
{
	Launcher* launcher;
	ItemList!(PluginPack*) pluginPacks;
	ItemList!(SaveInfo*) saves;

	void init(Launcher* launcher)
	{
		this.launcher = launcher;
	}

	void refresh()
	{
		pluginPacks.items = &launcher.pluginPacks;
		saves.items = &launcher.saves;
	}

	void draw()
	{
		igBeginGroup();
		withWidth!(150, igCombo3)(
			"Pack",
			cast(int*)&pluginPacks.currentItem,
			&itemGetter!(ItemList!(PluginPack*)), &pluginPacks,
			cast(int)pluginPacks.items.length, -1);
		igSameLine();
		withWidth!(150, igCombo3)(
			"Save",
			cast(int*)&saves.currentItem,
			&itemGetter!(ItemList!(SaveInfo*)), &saves,
			cast(int)saves.items.length, -1);
		igSameLine();
		startButtons(launcher, pluginPacks.selected, saves.selected);

		float areaHeight = igGetWindowHeight() - igGetCursorPosY() - 10;

		enum minItemHeight = 160;
		size_t numJobs = launcher.jobs.length;
		float itemHeight = (numJobs) ? areaHeight / numJobs : minItemHeight;
		if (itemHeight < minItemHeight) itemHeight = minItemHeight;
		foreach(job; launcher.jobs) drawJobLog(job, itemHeight);

		igEndGroup();
	}
}

void startButtons(Launcher* launcher, PluginPack* pack, SaveInfo* save)
{
	static JobParams params;
	if (pack) params.runParameters["pack"] = pack.id;
	if (save) params.runParameters["world_name"] = save.name;

	params.appType = AppType.client;
	if (igButton("Client")) launcher.createJob(params); igSameLine();

	params.appType = AppType.server;
	if (igButton("Server")) launcher.createJob(params); igSameLine();

	params.appType = AppType.combined;
	if (igButton("Combined")) launcher.createJob(params);
}

void jobParams(JobParams* params)
{
	igCheckbox("nodeps", cast(bool*)&params.nodeps); igSameLine();
	igCheckbox("force", cast(bool*)&params.force); igSameLine();
	igCheckbox("x64", cast(bool*)&params.arch64); igSameLine();
	//igCheckbox("release", cast(bool*)&params.release); igSameLine();

	withWidth!(60, igCombo2)("##buildType", cast(int*)&params.buildType, buildTypeUiSelectionString.ptr, 4); igSameLine();
	withWidth!(40, igCombo2)("##compiler", cast(int*)&params.compiler, compilerUiSelectionString.ptr, 2);
}

void drawJobLog(J)(J* job, float height)
{
	igPushIdPtr(job);
	assert(job.title.ptr);
	auto state = jobStateString(job);
	auto textPtrs = makeFormattedTextPtrs("%s %s\0", state, job.title);

	igBeginChildEx(igGetIdPtr(job), ImVec2(0, height), true, ImGuiWindowFlags_HorizontalScrollbar);
		igTextUnformatted(textPtrs.start, textPtrs.end-1);
		igSameLine();
		jobParams(&job.params);
		igSameLine();
		drawActionButtons(job);
		if (job.command)
		{
			igPushItemWidth(-1);
			igInputText("", cast(char*)job.command.ptr, job.command.length, ImGuiInputTextFlags_ReadOnly);
			igPopItemWidth();
		}
		job.messageWindow.draw();
	igEndChild();

	igPopId();
}

void drawActionButtons(J)(J* job)
{
	if (igButton("Clear")) job.messageWindow.lineBuffer.clear();
	if (!job.isRunning && !job.needsRestart) {
		igSameLine();
		if (igButton("Close")) job.needsClose = true;
		igSameLine();

		int jobType = int.max;
		if (igButton(" Run ")) jobType = JobType.run; igSameLine();
		if (igButton("Build")) jobType = JobType.compile; igSameLine();
		if (igButton(" B&R ")) jobType = JobType.compileAndRun;
		if (jobType != int.max)
		{
			job.needsRestart = true;
			job.params.jobType = cast(JobType)jobType;
		}
	} else {
		igSameLine();
		if (igButton("Stop")) job.sendCommand("stop");
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
	//style.Colors[ImGuiCol_ModalWindowDarkening]  = ImVec4(1.00f, 1.00f, 1.00f, 1.00f);
	style.WindowFillAlphaDefault = 1.0f;
}

enum mainWindowFlags = ImGuiWindowFlags_NoTitleBar |
	ImGuiWindowFlags_NoResize |
	ImGuiWindowFlags_NoMove |
	ImGuiWindowFlags_NoCollapse |
	ImGuiWindowFlags_NoSavedSettings;
	//ImGuiWindowFlags_MenuBar;
