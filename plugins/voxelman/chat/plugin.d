module voxelman.chat.plugin;

import voxelman.log;
import pluginlib;
import voxelman.text.messagewindow : MessageWindow;

import voxelman.core.events;
import voxelman.net.events;
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
		evDispatcher.subscribeToEvent(&onMessageEvent);

		connection = pluginman.getPlugin!NetClientPlugin;
	}

	void onMessageEvent(ref MessageEvent event)
	{
		if (event.endpoint == MessageEndpoint.chat)
		{
			// TODO
			info(event.msg);
		}
	}
}

final class ChatPluginServer : IPlugin
{
	// IPlugin stuff
	mixin IdAndSemverFrom!"voxelman.chat.plugininfo";

	private NetServerPlugin connection;
	private ClientManager clientMan;

	override void init(IPluginManager pluginman)
	{
		connection = pluginman.getPlugin!NetServerPlugin;
		clientMan = pluginman.getPlugin!ClientManager;
		auto commandPlugin = pluginman.getPlugin!CommandPluginServer;
		commandPlugin.registerCommand(CommandInfo("msg", &messageCommand, ["<message>"], "Sends a chat message to all clients"));
	}

	void messageCommand(CommandParams params)
	{
		auto strippedMsg = params.rawStrippedArgs;
		connection.sendToAll(MessagePacket(strippedMsg, params.sourceType));
	}

	void onMessageEvent(ref MessageEvent event)
	{
		if (event.endpoint == MessageEndpoint.chat)
		{
			connection.sendToAll(event.packet);
			infof("%s> %s", event.clientName, event.msg);
		}
	}
}
