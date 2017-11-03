module voxelman.chat.plugin;

import voxelman.log;
import pluginlib;
import voxelman.text.messagewindow : MessageWindow;

import voxelman.core.events;
import voxelman.net.packets;

import voxelman.command.plugin;
import voxelman.eventdispatcher.plugin;
import voxelman.net.plugin;
import voxelman.session;


final class ChatPluginClient : IPlugin
{
	// IPlugin stuff
	mixin IdAndSemverFrom!"voxelman.chat.plugininfo";

	private ClientSession session;
	private NetClientPlugin connection;
	private EventDispatcherPlugin evDispatcher;
	//MessageWindow messageWindow;
	float alpha;

	override void preInit()
	{
		//messageWindow.init();
		//messageWindow.messageHandler =
		//	(string msg) => connection.send(MessagePacket(msg), 1);
	}

	override void init(IPluginManager pluginman)
	{
		session = pluginman.getPlugin!ClientSession;
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		evDispatcher.subscribeToEvent(&onUpdateEvent);

		connection = pluginman.getPlugin!NetClientPlugin;
		connection.registerPacketHandler!MessagePacket(&handleMessagePacket);
	}

	void handleMessagePacket(ubyte[] packetData)
	{
		import std.format : formattedWrite;
		auto packet = unpackPacket!MessagePacket(packetData);

		//if (packet.clientId == 0)
		//	messageWindow.putln(packet.msg);
		//else {
		//	messageWindow.putf("%s> %s\n", session.clientName(packet.clientId), packet.msg);
		//}
	}

	void onUpdateEvent(ref UpdateEvent event)
	{

	}
}

final class ChatPluginServer : IPlugin
{
	// IPlugin stuff
	mixin IdAndSemverFrom!"voxelman.chat.plugininfo";

	private NetServerPlugin connection;
	private ClientManager clientMan;
	CommandPluginServer commandPlugin;

	override void init(IPluginManager pluginman)
	{
		connection = pluginman.getPlugin!NetServerPlugin;
		connection.registerPacketHandler!MessagePacket(&handleMessagePacket);
		clientMan = pluginman.getPlugin!ClientManager;
		commandPlugin = pluginman.getPlugin!CommandPluginServer;
		commandPlugin.registerCommand("msg", &messageCommand);
	}

	void handleMessagePacket(ubyte[] packetData, SessionId sessionId)
	{
		auto packet = unpackPacket!MessagePacket(packetData);
		Session* session = clientMan.sessions[sessionId];
		packet.clientId = session.dbKey;
		connection.sendToAll(packet);
		infof("%s> %s", clientMan.clientName(sessionId), packet.msg);
	}

	void messageCommand(CommandParams params)
	{
		auto stripped = params.rawStrippedArgs;
		connection.sendToAll(MessagePacket(stripped));
		infof("> %s", stripped);
	}
}
