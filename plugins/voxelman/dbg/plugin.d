/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.dbg.plugin;

import voxelman.log;
import std.array;
import std.container.rbtree;
import pluginlib;
import derelict.imgui.imgui;
import voxelman.core.events;
import voxelman.eventdispatcher.plugin;
import voxelman.net.plugin;
import voxelman.utils.textformatter;

alias DebugGuiHandler = void delegate();

enum FPS_ORDER = 0;
enum INFO_ORDER = 50;
enum DEBUG_ORDER = 100;
enum SETTINGS_ORDER = 200;

struct DebugGuiHandlerItem
{
	int order;
	string name;
	DebugGuiHandler handler;

	int opCmp(ref const DebugGuiHandlerItem other) const {
		int orderDiff = other.order - order;
		if (orderDiff == 0) return other.name < name;
		return orderDiff;
	}
}

final class DebugClient : IPlugin
{
	mixin IdAndSemverFrom!"voxelman.dbg.plugininfo";

	Debugger dbg;
	NetClientPlugin connection;
	RedBlackTree!(DebugGuiHandlerItem, "a>b") handlerList;

	override void registerResourceManagers(void delegate(IResourceManager) registerHandler)
	{
		registerHandler(dbg = new Debugger);
	}

	override void preInit()
	{
		handlerList = new typeof(handlerList);
		registerDebugGuiHandler(&drawDebugGroup, DEBUG_ORDER, "Debug");
	}

	override void init(IPluginManager pluginman)
	{
		auto evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&handleDoGuiEvent);
		connection = pluginman.getPlugin!NetClientPlugin;
		connection.registerPacket!TelemetryPacket(&handleTelemetryPacket);
	}

	// bigger order items go lower in menu
	void registerDebugGuiHandler(DebugGuiHandler handler, int order, string name)
	{
		handlerList.insert(DebugGuiHandlerItem(order, name, handler));
	}

	void handleDoGuiEvent(ref DoGuiEvent event)
	{
		igSetNextWindowSize(ImVec2(225, 350), ImGuiSetCond_Once);
		igSetNextWindowPos(ImVec2(0, 0), ImGuiSetCond_Once);
		igBegin("Debug");
		foreach(item; handlerList[])
		{
			item.handler();
		}
		igEnd();
	}

	private void drawDebugGroup()
	{
		if (igCollapsingHeader("Debug"))
		{
			foreach(key, var; dbg.vars) {
				igTextf("%s: %s", key, var);
			}
			foreach(key, ref buf; dbg.buffers) {
				igPlotLines2(key.ptr, &get_val, cast(void*)&buf, cast(int)buf.maxLen, cast(int)buf.next);
			}
		}
	}

	private void handleTelemetryPacket(ubyte[] packetData)
	{
		auto packet = unpackPacketNoDup!TelemetryPacket(packetData);
		dbg.setVar(packet.name, packet.val);
	}
}

extern(C) float get_val(void* data, int index)
{
	VarBuffer* buf = cast(VarBuffer*)data;
	return buf.vals[index % buf.maxLen];
}

final class DebugServer : IPlugin
{
	mixin IdAndSemverFrom!"voxelman.dbg.plugininfo";

	Debugger dbg;
	NetServerPlugin connection;

	override void init(IPluginManager pluginman)
	{
		auto evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&handlePostUpdateEvent);
		connection = pluginman.getPlugin!NetServerPlugin;
		connection.registerPacket!TelemetryPacket();
	}

	override void registerResourceManagers(void delegate(IResourceManager) registerHandler)
	{
		registerHandler(dbg = new Debugger);
	}

	void handlePostUpdateEvent(ref PostUpdateEvent event)
	{
		foreach(pair; dbg.vars.byKeyValue())
		{
			connection.sendToAll(TelemetryPacket(pair.key, pair.value));
		}
	}
}

struct VarBuffer
{
	this(double initVal, size_t _maxLen) {
		maxLen = _maxLen;
		vals = uninitializedArray!(double[])(maxLen);
		vals[0] = initVal;
		vals[1..$] = 0;
		length = 1;
		next = 1;
	}
	void insert(double val)
	{
		vals[next] = val;
		next = (next + 1) % maxLen;
		length = (length + 1) % maxLen;
	}
	@disable this();
	double[] vals;
	size_t next;
	size_t length;
	size_t maxLen;
}


final class Debugger : IResourceManager
{
	override string id() @property { return "voxelman.dbg.debugger"; }
	VarBuffer[string] buffers;
	double[string] vars;

	void logVar(string name, double val, size_t maxLen)
	{
		if (auto buf = name in buffers)
			buf.insert(val);
		else
			buffers[name] = VarBuffer(val, maxLen);
	}

	void setVar(string name, double val)
	{
		vars[name] = val;
	}

	void clearVar(string name)
	{
		buffers.remove(name);
	}
}

struct TelemetryPacket
{
	string name;
	double val;
}
