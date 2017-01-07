/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.remotecontrol.plugin;

import std.stdio;
import voxelman.log;
import std.traits : Select;

import pluginlib;
import voxelman.core.events;
import voxelman.eventdispatcher.plugin;
import voxelman.command.plugin;
import voxelman.server.plugin;


final class RemoteControl(bool clientSide) : IPlugin
{
	alias CommandPlugin = Select!(clientSide, CommandPluginClient, CommandPluginServer);

	// IPlugin stuff
	mixin IdAndSemverFrom!"voxelman.remotecontrol.plugininfo";
	private EventDispatcherPlugin evDispatcher;
	private CommandPlugin commandPlugin;
	private char[] buf;

	override void preInit() {
		buf = new char[](2048);
	}

	override void init(IPluginManager pluginman)
	{
		evDispatcher = pluginman.getPlugin!EventDispatcherPlugin;
		commandPlugin = pluginman.getPlugin!CommandPlugin;
		bool enable = true;

		static if (!clientSide)
		{
			ServerPlugin serverPlugin = pluginman.findPlugin!ServerPlugin;
			bool serverPresent = serverPlugin !is null;
			enable = serverPresent && (serverPlugin.mode == ServerMode.standalone);
		}

		if (enable)
			evDispatcher.subscribeToEvent(&onPreUpdateEvent);
	}

	void onPreUpdateEvent(ref PreUpdateEvent event)
	{
		try readStdin();
		catch (Exception e) { warningf("Exception while reading stdin: %s", e); }
	}

	void readStdin()
	{
		if (!stdin.isOpen || stdin.eof || stdin.error) return;

		auto size = stdin.size;
		if (size > 0 && size != ulong.max)
		{
			import std.regex : ctRegex, splitter;
			import std.algorithm : min;
			import std.array : array;

			size_t charsToRead = min(size, buf.length);
			char[] data = stdin.rawRead(buf[0..charsToRead]);
			auto splittedLines = splitter(data, ctRegex!"(\r\n|\r|\n|\v|\f)").array;

			while (splittedLines.length > 1)
			{
				char[] command = splittedLines[0];
				splittedLines = splittedLines[1..$];

				ExecResult res = commandPlugin.execute(command, SessionId(0));

				if (res.status == ExecStatus.notRegistered)
				{
					warningf("Unknown command '%s'", command);
				}
				else if (res.status == ExecStatus.error)
					warningf("Error executing command '%s': %s", command, res.error);
			}

			if (splittedLines.length == 1)
				stdin.seek(-cast(long)splittedLines[0].length);
		}
	}
}
