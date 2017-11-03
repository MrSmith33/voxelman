/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.gui.plugin;

import voxelman.log;
import std.string : format;
import voxelman.math;

import voxelman.platform.iwindow;
import voxelman.platform.input;
import voxelman.gui;
import voxelman.graphics;
import voxelman.graphics.plugin;
import voxelman.text.linebuffer;

import pluginlib;

import voxelman.core.config;
import voxelman.core.events;
import voxelman.world.storage;

import voxelman.dbg.plugin;
import voxelman.eventdispatcher.plugin;
import voxelman.input.keybindingmanager;

struct ClosePressedEvent {}


final class GuiPlugin : IPlugin
{
private:
	EventDispatcherPlugin evDispatcher;
	GraphicsPlugin graphics;
	WidgetId highlightedWidget;

public:
	GuiContext guictx;
	IWindow window;
	bool mouseLocked;
	bool isGuiDebuggerShown;

	mixin IdAndSemverFrom!"voxelman.gui.plugininfo";

	override void registerResources(IResourceManagerRegistry resmanRegistry)
	{
		auto keyBindingMan = resmanRegistry.getResourceManager!KeyBindingManager;
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_Q, "key.lockMouse", null, &onLockMouse));
		keyBindingMan.registerKeyBinding(new KeyBinding(KeyCode.KEY_F9, "key.lockMouse", null, (s){isGuiDebuggerShown.toggle_bool;}));
		auto res = resmanRegistry.getResourceManager!GraphicsResources;
		guictx = res.guictx;
	}

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onPreUpdateEvent);
		evDispatcher.subscribeToEvent(&renderDebug);

		auto debugClient = pluginman.getPlugin!DebugClient;
		debugClient.registerDebugGuiHandler(&showDebugSettings, SETTINGS_ORDER, "Q Lock mouse");

		graphics = pluginman.getPlugin!GraphicsPlugin;
		window = graphics.window;

		createGuiDebugger();
	}

	private void showDebugSettings()
	{
		//igCheckbox("[Q] Lock mouse", &mouseLocked);
		updateMouseLock();
	}

	private void onPreUpdateEvent(ref PreUpdateEvent event)
	{
		updateMouseLock();
	}

	private void onLockMouse(string)
	{
		mouseLocked = !mouseLocked;
		updateMouseLock();
	}

	private void updateMouseLock()
	{
		if (window.isCursorLocked != mouseLocked)
		{
			window.isCursorLocked = mouseLocked;
			if (mouseLocked)
				window.mousePosition = cast(ivec2)(window.size) / 2;
		}
	}

	private void renderDebug(ref Render2Event event)
	{
		// highlight widget
		auto t = guictx.get!WidgetTransform(highlightedWidget);
		if (t) graphics.renderQueue.drawRectLine(vec2(t.absPos), vec2(t.size), 1000+10, Colors.red);
	}

	private void createGuiDebugger()
	{
		// Tree widget
		struct TreeNode
		{
			WidgetId wid;
			TreeLineType nodeType;
			int indent;
			int numExpandedChildren;
		}

		class WidgetTreeModel : ListModel
		{
			import std.format : formattedWrite;
			import voxelman.container.gapbuffer;
			GapBuffer!TreeNode nodeList;
			WidgetProxy widgetAt(size_t i) { return WidgetProxy(nodeList[i].wid, guictx); }
			int selectedLine = -1;
			ColumnInfo[2] columnInfos = [ColumnInfo("Type", 200), ColumnInfo("Id", 50, Alignment.max)];

			void clear()
			{
				nodeList.clear();
				selectedLine = -1;
			}

			override int numLines() { return cast(int)nodeList.length; }
			override int numColumns() { return 2; }
			override ref ColumnInfo columnInfo(int column) {
				return columnInfos[column];
			}
			override void getColumnText(int column, scope void delegate(const(char)[]) sink) {
				if (column == 0) sink("Widget type");
				else if (column == 1) sink("Widget id");
				else assert(false);
			}
			override void getCellText(int column, int line, scope void delegate(const(char)[]) sink) {
				if (column == 0) sink(widgetAt(line).widgetType);
				else formattedWrite(sink, "%s", nodeList[line].wid);
			}
			override bool isLineSelected(int line) { return line == selectedLine; }
			override void onLineClick(int line) {
				selectedLine = line;
				if (selectedLine == -1)
					highlightedWidget = 0;
				else
					highlightedWidget = nodeList[line].wid;
			}
			override TreeLineType getLineType(int line) {
				return nodeList[line].nodeType;
			}
			override int getLineIndent(int line) { return nodeList[line].indent; }
			override void toggleLineFolding(int line) {
				if (nodeList[line].nodeType == TreeLineType.collapsedNode) expandWidget(line);
				else collapseWidget(line);
			}
			void expandWidget(int line)
			{
				//writefln("expand %s %s", line, nodeList[line].wid);
				auto container = guictx.get!WidgetContainer(nodeList[line].wid);
				if (container is null || container.children.length == 0) {
					nodeList[line].nodeType = TreeLineType.leaf;
					return;
				}
				auto insertPos = line+1;
				auto indent = nodeList[line].indent+1;
				foreach(wid; container.children)
				{
					TreeLineType nodeType = numberOfChildren(guictx, wid) ? TreeLineType.collapsedNode : TreeLineType.leaf;
					nodeList.putAt(insertPos++, TreeNode(wid, nodeType, indent));
				}
				nodeList[line].nodeType = TreeLineType.expandedNode;
			}
			void collapseWidget(int line)
			{
				//writefln("collapse %s", line, nodeList[line].wid);
				if (line+1 == nodeList.length) {
					nodeList[line].nodeType = TreeLineType.leaf;
					return;
				}

				auto parentIndent = nodeList[line].indent;
				size_t numItemsToRemove;
				foreach(node; nodeList[line+1..$])
				{
					if (node.indent <= parentIndent) break;
					++numItemsToRemove;
				}
				nodeList.remove(line+1, numItemsToRemove);
				nodeList[line].nodeType = TreeLineType.collapsedNode;
			}
		}

		auto model = new WidgetTreeModel;
		auto tree_frame = Frame.create(guictx.getRoot(1));
		tree_frame.minSize(250, 500).pos(300, 10).makeDraggable.moveToTop.visible_if(() => isGuiDebuggerShown);
		tree_frame.container.setVLayout(2, padding4(2));
		tree_frame.header.setHLayout(2, padding4(4), Alignment.center);
		tree_frame.header.createIcon("tree", ivec2(16, 16), Colors.black);
		tree_frame.header.createText("Widget tree");
		auto widget_tree = ColumnListLogic.create(tree_frame.container, model).minSize(250, 400).hvexpand;

		void refillTree()
		{
			model.clear;
			foreach(rootId; guictx.roots)
			{
				TreeLineType nodeType = numberOfChildren(guictx, rootId) ? TreeLineType.collapsedNode : TreeLineType.leaf;
				model.nodeList.put(TreeNode(rootId, nodeType));
			}
		}
		refillTree();
		createTextButton(tree_frame.container, "Refresh", &refillTree).hexpand;
	}
}
