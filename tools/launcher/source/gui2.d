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

	AutoListModel!WorldList worldList;
	AutoListModel!ServerList serverList;

	this(string title, ivec2 windowSize)
	{
		super(title, windowSize);
		maxFps = 30;
		launcher.init();
		launcher.setRootPath(pluginFolder, pluginPackFolder, toolFolder);
		launcher.refresh();
	}

	override void load(string[] args)
	{
		super.load(args);
		WidgetProxy root = WidgetProxy(guictx.roots[0], guictx);
		createMain(root);
	}

	override void userUpdate(double delta)
	{
		launcher.update();
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
		right_panel.createText("Debug page");

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
				HFill.create(bottom_panel_worlds);
				bottom_panel_worlds.createTextButton("Server", &startServer).visible_if(&worldList.hasSelected);
				bottom_panel_worlds.createTextButton("Start", &startClient).visible_if(&worldList.hasSelected);

		VLine.create(play_panel);

		auto servers_panel = VLayout.create(play_panel, 0, padding4(1)).hvexpand;
			serverList = new AutoListModel!ServerList(ServerList(&launcher));
			auto list_servers = ColumnListLogic.create(servers_panel, serverList).minSize(320, 100).hvexpand;

			WidgetProxy bottom_panel_servers = HLayout.create(servers_panel, 2, padding4(1)).hexpand.addBackground(color_gray);
				bottom_panel_servers.createTextButton("New", &newServer);
				bottom_panel_servers.createTextButton("Remove", &removeServer).visible_if(&serverList.hasSelected);
				HFill.create(bottom_panel_servers);
				bottom_panel_servers.createTextButton("Connect", &connetToServer).visible_if(&serverList.hasSelected);

		return play_panel;
	}

	void newWorld() {}
	void removeWorld() {}
	void refreshWorlds() {
		launcher.refresh();
	}
	void startServer() {
		launcher.startServer(launcher.pluginPacks[0], launcher.saves[worldList.selectedRow]);
	}
	void startClient() {
		launcher.startCombined(launcher.pluginPacks[0], launcher.saves[worldList.selectedRow]);
	}

	void newServer() {}
	void removeServer() {}
	void connetToServer() {}
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
