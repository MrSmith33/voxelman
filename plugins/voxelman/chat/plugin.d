module voxelman.chat.plugin;

import std.experimental.logger;
import pluginlib;
import voxelman.utils.messagewindow : MessageWindow;

import voxelman.client.plugin;
import voxelman.server.plugin;
import voxelman.core.events;
import voxelman.eventdispatcher.plugin;
import voxelman.net.packets;
import voxelman.net.plugin;

shared static this()
{
	pluginRegistry.regClientPlugin(new ChatPluginClient);
	pluginRegistry.regServerPlugin(new ChatPluginServer);
}

final class ChatPluginClient : IPlugin
{
	// IPlugin stuff
	mixin IdAndSemverFrom!(voxelman.chat.plugininfo);

	private ClientPlugin clientPlugin;
	private NetClientPlugin connection;
	private EventDispatcherPlugin evDispatcher;
	MessageWindow messageWindow;

	override void preInit()
	{
		messageWindow.init();
		messageWindow.messageHandler =
			(string msg) => connection.send(MessagePacket(0, msg), 1);
	}

	override void init(IPluginManager pluginman)
	{
		clientPlugin = pluginman.getPlugin!ClientPlugin;
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onUpdateEvent);

		connection = pluginman.getPlugin!NetClientPlugin;
		connection.registerPacketHandler!MessagePacket(&handleMessagePacket);
	}

	void handleMessagePacket(ubyte[] packetData, ClientId clientId)
	{
		import std.format : formattedWrite;
		auto packet = unpackPacket!MessagePacket(packetData);

		if (packet.clientId == 0)
			messageWindow.putln(packet.msg);
		else {
			messageWindow.putf("%s> %s\n", clientPlugin.clientName(packet.clientId), packet.msg);
		}
	}

	void onUpdateEvent(ref UpdateEvent event)
	{
		import derelict.imgui.imgui;

		float h = 200;
		igSetNextWindowPos(ImVec2(0, igGetIO().DisplaySize.y-h), ImGuiSetCond_FirstUseEver);
		igSetNextWindowSize(ImVec2(500, h), ImGuiSetCond_FirstUseEver);
		if (!igBegin("Chat")) return;
		messageWindow.draw();
		igEnd();
	}
}

final class ChatPluginServer : IPlugin
{
	// IPlugin stuff
	mixin IdAndSemverFrom!(voxelman.chat.plugininfo);

	private NetServerPlugin connection;
	private ServerPlugin serverPlugin;
	CommandPluginServer commandPlugin;

	override void init(IPluginManager pluginman)
	{
		connection = pluginman.getPlugin!NetServerPlugin;
		connection.registerPacketHandler!MessagePacket(&handleMessagePacket);
		serverPlugin = pluginman.getPlugin!ServerPlugin;
		commandPlugin = pluginman.getPlugin!CommandPluginServer;
		commandPlugin.registerCommand("msg", &messageCommand);
	}

	void handleMessagePacket(ubyte[] packetData, ClientId clientId)
	{
		auto packet = unpackPacket!MessagePacket(packetData);
		packet.clientId = clientId;
		connection.sendToAll(packet);
		infof("%s> %s", serverPlugin.clientName(clientId), packet.msg);
	}

	void messageCommand(CommandParams params)
	{
		import std.string : strip;
		auto stripped = params.rawArgs.strip;
		connection.sendToAll(MessagePacket(0, stripped));
		infof("> %s", stripped);
	}
}
