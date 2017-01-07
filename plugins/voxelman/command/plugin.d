/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.command.plugin;

import netlib;
import pluginlib;
public import netlib : SessionId;
public import std.getopt;
import voxelman.log;
import std.string : format;

struct CommandParams
{
	string rawArgs; // without command name
	auto rawStrippedArgs() @property
	{
		import std.string : strip;
		return rawArgs.strip;
	}
	string[] args; // first arg is command name. Use with getopt.
	SessionId source;
}

// On client side source == 0
// On server if command is issued locally source == 0
// First argument is command name (useful for std.getopt)
alias CommandHandler = void delegate(CommandParams params);

enum ExecStatus
{
	success,
	notRegistered,
	//invalidArgs,
	error
}

struct ExecResult
{
	string[] args;
	ExecStatus status;
	string error;
}

final class CommandPluginClient : IPlugin
{
	mixin CommandPluginCommon;
}

final class CommandPluginServer : IPlugin
{
	mixin CommandPluginCommon;
	mixin CommandPluginServerImpl;
}

mixin template CommandPluginCommon()
{
	// IPlugin stuff
	mixin IdAndSemverFrom!"voxelman.command.plugininfo";

	CommandHandler[string] handlers;

	void registerCommand(string commandName, CommandHandler handler)
	{
		import std.algorithm : splitter;
		foreach(comAlias; commandName.splitter('|'))
		{
			assert(comAlias !in handlers, comAlias ~ " command is already registered");
			handlers[comAlias] = handler;
		}
	}

	ExecResult execute(const(char)[] input, SessionId source = SessionId(0))
	{
		import std.regex : ctRegex, splitter;
		import std.string : strip;
		import std.array : array;

		string stripped = cast(string)input.strip;
		string[] args = splitter(stripped, ctRegex!`\s+`).array;

		if (args.length == 0)
			return ExecResult(args, ExecStatus.notRegistered);

		string comName = args[0];
		string rawArgs = stripped[args[0].length..$];

		if (auto handler = handlers.get(cast(string)comName, null))
		{
			try
			{
				handler(CommandParams(rawArgs, args, source));
			}
			catch(Exception e)
			{
				return ExecResult(args, ExecStatus.error, e.msg);
			}
		}
		else
		{
			return ExecResult(args, ExecStatus.notRegistered);
		}

		return ExecResult(args, ExecStatus.success);
	}
}

mixin template CommandPluginServerImpl()
{
	import voxelman.net.plugin : NetServerPlugin;
	import voxelman.core.packets : CommandPacket;
	import voxelman.net.packets : MessagePacket;
	import voxelman.session.server;

	NetServerPlugin connection;
	ClientManager clientMan;

	override void init(IPluginManager pluginman)
	{
		connection = pluginman.getPlugin!NetServerPlugin;
		connection.registerPacketHandler!CommandPacket(&handleCommandPacket);
		clientMan = pluginman.getPlugin!ClientManager;
	}

	void handleCommandPacket(ubyte[] packetData, SessionId sessionId)
	{
		if (sessionId != 0) // not server
		{
			if (!clientMan.isLoggedIn(sessionId))
			{
				connection.sendTo(sessionId, MessagePacket("Log in to use commands"));
				return;
			}
		}
		auto packet = unpackPacket!CommandPacket(packetData);

		ExecResult res = execute(packet.command, sessionId);

		if (res.status == ExecStatus.notRegistered)
			connection.sendTo(sessionId, MessagePacket(format("Unknown command '%s'", packet.command)));
		else if (res.status == ExecStatus.error)
			connection.sendTo(sessionId,
				MessagePacket(format("Error executing command '%s': %s", packet.command, res.error)));
	}
}
