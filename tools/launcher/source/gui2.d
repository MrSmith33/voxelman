/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module gui2;

import std.format : formattedWrite;
import std.stdio;
import voxelman.math;
import voxelman.gui;
import voxelman.gui.textedit.lineedit;
import voxelman.gui.textedit.messagelog;
import voxelman.gui.textedit.textmodel;
import voxelman.gui.textedit.texteditorview;
import voxelman.graphics;
import voxelman.text.scale;

import launcher;
import voxelman.gui.guiapp;

class LauncherGui : GuiApp
{
	Launcher launcher;

	string pluginFolder = `./plugins`;
	string pluginPackFolder = `./pluginpacks`;
	string toolFolder = `./tools`;
	string resFolder = `./res`;

	AutoListModel!WorldList worldList;
	AutoListModel!ServerList serverList;
	WidgetProxy job_stack;
	TextViewSettings textSettings;
	bool isGuiDebuggerShown;

	this(string title, ivec2 windowSize)
	{
		super(title, windowSize);
		maxFps = 30;
		launcher.init();
		launcher.setRootPath(pluginFolder, pluginPackFolder, toolFolder);
		launcher.refresh();
	}

	override void load(string[] args, string resPath)
	{
		super.load(args, resFolder);
		textSettings = TextViewSettings(renderQueue.defaultFont);
		createMain(guictx.getRoot(0));
		// showDebugInfo = true;
		// isGuiDebuggerShown = true;

		auto debugger_frame = createGuiDebugger(guictx.getRoot(1));
		debugger_frame.visible_if(() => isGuiDebuggerShown);
	}

	override void userPreUpdate(double delta)
	{
		launcher.update();
	}

	override void closePressed()
	{
		if (!launcher.anyProcessesRunning)
		{
			isClosePressed = true;
		}
	}

	void createMain(WidgetProxy root)
	{
		HLayout.attachTo(root, 0, padding4(0));

		WidgetProxy left_panel = PanelLogic.create(root, color_gray)
			.minSize(ivec2(60, 0))
			.vexpand
			.setVLayout(3, padding4(3, 0, 3, 3));

		WidgetProxy right_panel = VLayout.create(root, 0, padding4(0)).hvexpand;

		left_panel.createIconTextButton("play", "Play", () => PagedWidget.switchPage(right_panel, 0)).hexpand;
		left_panel.createIconTextButton("hammer", "Debug", () => PagedWidget.switchPage(right_panel, 1)).hexpand;

		createPlay(right_panel);
		createDebug(right_panel);

		PagedWidget.convert(right_panel, 0);
	}

	WidgetProxy createPlay(WidgetProxy parent)
	{
		auto play_panel = HLayout.create(parent, 0, padding4(0)).hvexpand;

		auto worlds_panel = VLayout.create(play_panel, 0, padding4(1)).hvexpand;

			worldList = new AutoListModel!WorldList(WorldList(&launcher));
			auto list_worlds = ColumnListLogic.create(worlds_panel, worldList).minSize(260, 100).hvexpand;

			WidgetProxy bottom_panel_worlds = HLayout.create(worlds_panel, 2, padding4(1)).hexpand.addBackground(color_gray);
				bottom_panel_worlds.createTextButton("New", &newWorld);
				bottom_panel_worlds.createTextButton("Remove", &removeWorld).visible_if(&worldList.hasSelected);
				bottom_panel_worlds.createTextButton("Refresh", &refreshWorlds);
				bottom_panel_worlds.hfill;
				bottom_panel_worlds.createTextButton("Server", &startServer).visible_if(&worldList.hasSelected);
				bottom_panel_worlds.createTextButton("Start", &startClient).visible_if(&worldList.hasSelected);

		VLine.create(play_panel);

		auto servers_panel = VLayout.create(play_panel, 0, padding4(1)).hvexpand;
			serverList = new AutoListModel!ServerList(ServerList(&launcher));
			auto list_servers = ColumnListLogic.create(servers_panel, serverList).minSize(320, 100).hvexpand;

			WidgetProxy bottom_panel_servers = HLayout.create(servers_panel, 2, padding4(1)).hexpand.addBackground(color_gray);
				bottom_panel_servers.createTextButton("New", &newServer);
				bottom_panel_servers.createTextButton("Remove", &removeServer).visible_if(&serverList.hasSelected);
				bottom_panel_servers.hfill;
				bottom_panel_servers.createTextButton("Connect", &connetToServer).visible_if(&serverList.hasSelected);

		return play_panel;
	}

	WidgetProxy createDebug(WidgetProxy parent)
	{
		auto debug_panel = VLayout.create(parent, 0, padding4(0)).hvexpand;
		auto top_buttons = HLayout.create(debug_panel, 2, padding4(1)).hexpand;

		TextButtonLogic.create(top_buttons, "Client", &startClient_debug);
		TextButtonLogic.create(top_buttons, "Server", &startServer_debug);
		TextButtonLogic.create(top_buttons, "Combined", &startCombined_debug);

		job_stack = VLayout.create(debug_panel, 0, padding4(0)).hvexpand;

		return debug_panel;
	}

	void newWorld() {}
	void removeWorld() {}
	void refreshWorlds() {
		launcher.refresh();
	}
	void startServer() {
		auto job = launcher.startServer(launcher.pluginPacks[0], launcher.saves[worldList.selectedRow]);
		if (job) JobItemWidget.create(job_stack, job, &textSettings);
	}
	void startClient() {
		auto job = launcher.startCombined(launcher.pluginPacks[0], launcher.saves[worldList.selectedRow]);
		if (job) JobItemWidget.create(job_stack, job, &textSettings);
	}

	void newServer() {}
	void removeServer() {}
	void connetToServer() {
		launcher.connect(launcher.servers[serverList.selectedRow], launcher.pluginPacks[0]); }

	void startClient_debug() { createJob(AppType.client); }
	void startServer_debug() { createJob(AppType.server); }
	void startCombined_debug() { createJob(AppType.combined); }

	void createJob(AppType appType)
	{
		JobParams params;
		params.appType = appType;
		Job* job = launcher.createJob(params);
		JobItemWidget.create(job_stack, job, &textSettings);
	}
}

struct JobItemWidget
{
	static:
	WidgetProxy create(WidgetProxy parent, Job* job, TextViewSettingsRef textSettings)
	{
		parent.ctx.style.pushColor(color_wet_asphalt);

		auto job_item = VLayout.create(parent, 0, padding4(0)).hvexpand;
		auto top_buttons = HLayout.create(job_item, 2, padding4(3,3,1,1), Alignment.center).hexpand.addBorder(color_gray);
		bool job_running() { return !job.isRunning && !job.needsRestart; }

		void updateStatusText(WidgetProxy widget, ref GuiUpdateEvent event)
		{
			if (event.bubbling) return;
			TextLogic.setText(widget, jobStateString(job));
		}
		createText(top_buttons, jobStateString(job)).handlers(&updateStatusText);

		createCheckButton(top_buttons, "nodeps", cast(bool*)&job.params.nodeps);
		createCheckButton(top_buttons, "force", cast(bool*)&job.params.force);
		createCheckButton(top_buttons, "x64", cast(bool*)&job.params.arch64);
		DropDown.create(top_buttons, buildTypeUiOptions, 0, (size_t opt){job.params.buildType = cast(BuildType)opt;});
		DropDown.create(top_buttons, compilerUiOptions, 0, (size_t opt){job.params.compiler = cast(Compiler)opt;});
		createTextButton(top_buttons, "Clear", { job.msglog.clear; });
		createTextButton(top_buttons, "Close", { job.needsClose = true; }).visible_if(&job_running);

		void startJob(JobType t)() { job.params.jobType = t; job.needsRestart = true; }

		createTextButton(top_buttons, "Test",  &startJob!(JobType.test)).visible_if(&job_running);
		createTextButton(top_buttons, " Run ", &startJob!(JobType.run)).visible_if(&job_running);
		createTextButton(top_buttons, "Build", &startJob!(JobType.compile)).visible_if(&job_running);
		createTextButton(top_buttons, " B&R ", &startJob!(JobType.compileAndRun)).visible_if(&job_running);
		createTextButton(top_buttons, "Stop", { job.sendCommand("stop"); }).visible_if_not(&job_running);

		job.onClose ~= { job_item.ctx.removeWidget(job_item.wid); };

		job.msglog.setClipboard = parent.ctx.state.setClipboard;
		auto msglogModel = new MessageLogTextModel(&job.msglog);
		auto viewport = TextEditorViewportLogic.create(job_item, msglogModel, textSettings).hvexpand;

		hline(job_item);
		auto input = LineEdit.create(job_item).hexpand;

		void enterHandler(string com)
		{
			sendCommand(job, com);
			LineEdit.clear(input);
		}

		LineEdit.setEnterHandler(input, &enterHandler);

		void autoscroll_enable() { viewport.get!TextEditorViewportData.autoscroll = true; }
		bool autoscroll_enabled() { return viewport.get!TextEditorViewportData.autoscroll; }

		top_buttons.hfill;
		createTextButton(top_buttons, "Autoscroll", &autoscroll_enable).visible_if_not(&autoscroll_enabled);

		autoscroll_enable();

		parent.ctx.style.popColor;

		return job_item;
	}
}

struct WorldList
{
	Launcher* launcher;
	WorldRow opIndex(size_t i) { return WorldRow(*launcher.saves[i]); }
	size_t length() { return launcher.saves.length; }
}

struct WorldRow
{
	this(SaveInfo info) {
		this.filename = info.name;
		this.fileSize = info.size;
	}
	@Column!WorldRow("Name", 200, (WorldRow r, scope SinkT s){ s(r.filename); })
	string filename;

	@Column!WorldRow("Size", 60, (WorldRow r, scope SinkT s){ formattedWrite(s, "%sB", scaledNumberFmt(r.fileSize)); })
	ulong fileSize;
}

struct ServerList
{
	Launcher* launcher;
	ServerRow opIndex(size_t i) { return ServerRow(*launcher.servers[i]); }
	size_t length() { return launcher.servers.length; }
}

struct ServerRow
{
	this(ServerInfo info) {
		this.name = info.name;
		this.ip = info.ip;
		this.port = info.port;
	}
	@Column!ServerRow("Name", 150, (ServerRow r, scope SinkT s){ s(r.name); })
	string name;
	@Column!ServerRow("IP", 130, (ServerRow r, scope SinkT s){ s(r.ip); })
	string ip;
	@Column!ServerRow("Port", 40, (ServerRow r, scope SinkT s){ formattedWrite(s, "%s", r.port); })
	ushort port;
}
