module voxelman.chat.plugin;

import std.experimental.logger;
import pluginlib;
import voxelman.utils.linebuffer : LineBuffer;

import voxelman.client.plugin;
import voxelman.core.events;
import voxelman.eventdispatcher.plugin;
import voxelman.net.packets;
import voxelman.net.plugin;

shared static this()
{
	pluginRegistry.regClientPlugin(new ChatPlugin);
	//pluginRegistry.regServerPlugin(new ChatPlugin);
}

final class ChatPlugin : IPlugin
{
	// IPlugin stuff
	mixin IdAndSemverFrom!(voxelman.chat.plugininfo);

	private ClientPlugin clientPlugin;
	private NetClientPlugin connection;
	private EventDispatcherPlugin evDispatcher;
	LineBuffer lineBuffer;
	char[512] buf;

	override void preInit() {}
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
		infof("message received %s '%s' buflen %s",
			clientPlugin.clientName(packet.clientId),
			packet.msg, lineBuffer.lineSizes.data.length);
		if (packet.clientId == 0)
			lineBuffer.putln(packet.msg);
		else {
			lineBuffer.putf("%s> %s\n", clientPlugin.clientName(packet.clientId), packet.msg);
		}
	}

	void onUpdateEvent(ref UpdateEvent event)
	{
		import derelict.imgui.imgui;
		import std.string;
		igBegin("Chat");
		igBeginChildEx(0, ImVec2(0,-igGetItemsLineHeightWithSpacing()),
			true, ImGuiWindowFlags_HorizontalScrollbar);
		lineBuffer.draw();
		igEndChild();
		igSetNextWindowSize(ImVec2(0,0));
		if (igInputText("##Input", buf.ptr, buf.length,
			ImGuiInputTextFlags_EnterReturnsTrue,
			null, null))
		{
			auto msg = cast(string)(buf.ptr.fromStringz).strip;
			if (msg.length > 0)
			{
				connection.send(MessagePacket(0, msg), 1);
				buf[] = '\0';
			}
			if (igIsItemHovered() || (igIsRootWindowOrAnyChildFocused() && !igIsAnyItemActive() && !igIsMouseClicked(0)))
				igSetKeyboardFocusHere(-1); // Auto focus previous widget
		}

		igEnd();
	}
}
