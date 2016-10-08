module voxelman.chat.plugin;

import voxelman.log;
import pluginlib;
import voxelman.utils.messagewindow : MessageWindow;

import voxelman.core.events;
import voxelman.net.packets;

import voxelman.command.plugin;
import voxelman.eventdispatcher.plugin;
import voxelman.net.plugin;
import voxelman.login.plugin;

shared static this()
{
	pluginRegistry.regClientPlugin(new ChatPluginClient);
	pluginRegistry.regServerPlugin(new ChatPluginServer);
}

final class ChatPluginClient : IPlugin
{
	// IPlugin stuff
	mixin IdAndSemverFrom!(voxelman.chat.plugininfo);

	private ClientDbClient clientDb;
	private NetClientPlugin connection;
	private EventDispatcherPlugin evDispatcher;
	MessageWindow messageWindow;
	float alpha;

	override void preInit()
	{
		messageWindow.init();
		messageWindow.messageHandler =
			(string msg) => connection.send(MessagePacket(0, msg), 1);
	}

	override void init(IPluginManager pluginman)
	{
		clientDb = pluginman.getPlugin!ClientDbClient;
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
			messageWindow.putf("%s> %s\n", clientDb.clientName(packet.clientId), packet.msg);
		}
	}

	void onUpdateEvent(ref UpdateEvent event)
	{
		import derelict.imgui.imgui;

		float h = 200;
		igSetNextWindowPos(ImVec2(0, igGetIO().DisplaySize.y-h), ImGuiSetCond_Always);
		igSetNextWindowSize(ImVec2(400, h), ImGuiSetCond_Always);
		if (!igBegin2("Chat", null, ImVec2(0,0), 0.0f,
			ImGuiWindowFlags_NoTitleBar|ImGuiWindowFlags_NoResize|
			ImGuiWindowFlags_NoMove|ImGuiWindowFlags_NoSavedSettings))
		{
			igEnd();
			return;
		}
		//if (!igBegin("Chat")) return;
		messageWindow.draw();
		igEnd();
	}
}

final class ChatPluginServer : IPlugin
{
	// IPlugin stuff
	mixin IdAndSemverFrom!(voxelman.chat.plugininfo);

	private NetServerPlugin connection;
	private ClientDbServer clientDb;
	CommandPluginServer commandPlugin;

	override void init(IPluginManager pluginman)
	{
		connection = pluginman.getPlugin!NetServerPlugin;
		connection.registerPacketHandler!MessagePacket(&handleMessagePacket);
		clientDb = pluginman.getPlugin!ClientDbServer;
		commandPlugin = pluginman.getPlugin!CommandPluginServer;
		commandPlugin.registerCommand("msg", &messageCommand);
	}

	void handleMessagePacket(ubyte[] packetData, ClientId clientId)
	{
		auto packet = unpackPacket!MessagePacket(packetData);
		packet.clientId = clientId;
		connection.sendToAll(packet);
		infof("%s> %s", clientDb.clientName(clientId), packet.msg);
	}

	void messageCommand(CommandParams params)
	{
		auto stripped = params.rawStrippedArgs;
		connection.sendToAll(MessagePacket(0, stripped));
		infof("> %s", stripped);
	}
}
