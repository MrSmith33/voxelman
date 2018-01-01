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
import voxelman.text.textsink : TextSink;
import voxelman.core.packets : CommandPacket;
public import voxelman.core.packets : CommandSourceType;

// On client side source == 0
// On server if command is issued locally source == 0
// First argument is command name (useful for std.getopt)
alias CommandHandler = void delegate(CommandParams params);

struct CommandInfo
{
	string names;
	CommandHandler handler;
	string[] paramUsage;
	string helpMessage;
}

struct CommandParams
{
	string rawArgs; // without command name
	auto rawStrippedArgs() @property
	{
		import std.string : strip;
		return rawArgs.strip;
	}
	string[] args; // first arg is command name. Use with getopt.
	SessionId sourceSession;
	CommandSourceType sourceType;
	TextSink* textOutput;
}

enum ExecStatus
{
	success,
	noCommandGiven, // can be safely ignored
	notRegistered,
	notRegisteredRedirected, // redirect to server
	//invalidArgs,
	error
}

final class CommandPluginClient : IPlugin
{
	mixin CommandPluginCommon!false;

	import voxelman.net.plugin : NetClientPlugin;
	NetClientPlugin connection;

	override void preInit()
	{
		executorName = "CL";
		registerCommand(CommandInfo("help|cl_help", &onHelpCommand));
	}

	override void init(IPluginManager pluginman)
	{
		connection = pluginman.getPlugin!NetClientPlugin;
	}
}

final class CommandPluginServer : IPlugin
{
	mixin CommandPluginCommon!true;

	import voxelman.net.plugin : NetServerPlugin;
	import voxelman.net.packets : MessagePacket, commandSourceToMsgEndpoint;
	import voxelman.session.server;

	NetServerPlugin connection;
	ClientManager clientMan;

	override void preInit()
	{
		executorName = "SV";
	}

	override void init(IPluginManager pluginman)
	{
		connection = pluginman.getPlugin!NetServerPlugin;
		connection.registerPacketHandler!CommandPacket(&handleCommandPacket);
		clientMan = pluginman.getPlugin!ClientManager;

		registerCommand(CommandInfo("help|sv_help", &onHelpCommand));
	}

	// server command entry point. Command can come from network or from launcher (stdio)
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

		if (packet.sourceType == CommandSourceType.localLauncher)
			packet.sourceType = CommandSourceType.clientLauncher;

		execute(packet.command, packet.sourceType, sessionId);
		connection.sendTo(sessionId, MessagePacket(commandTextOutput.text, 0, commandSourceToMsgEndpoint[packet.sourceType]));
	}
}

mixin template CommandPluginCommon(bool isServer)
{
	// IPlugin stuff
	mixin IdAndSemverFrom!"voxelman.command.plugininfo";

	CommandInfo[] commands;
	CommandInfo[string] commandMap;
	TextSink commandTextOutput;
	string executorName; // SV or CL

	void registerCommand(CommandInfo command)
	{
		import std.algorithm : splitter;

		foreach(comAlias; command.names.splitter('|'))
		{
			assert(comAlias !in commandMap, comAlias ~ " command is already registered");
			commandMap[comAlias] = command;
		}
		commands ~= command;
	}

	void onHelpCommand(CommandParams params)
	{
		foreach (ref command; commands)
		{
			params.textOutput.putfln("% 20s  %s  %s", command.names, command.paramUsage, command.helpMessage);
		}

		// Also redirect to server
		static if(!isServer)
		{
			if (connection.isConnected) connection.send(CommandPacket("help", params.sourceType));
		}
	}

	// Command output is given in commandTextOutput
	ExecStatus execute(const(char)[] input, CommandSourceType sourceType, SessionId source = SessionId(0))
	{
		import std.regex : regex, splitter;
		import std.string : strip;
		import std.array : array;

		commandTextOutput.clear;

		string stripped = cast(string)input.strip;
		string[] args = splitter(stripped, regex(`\s+`)).array;

		if (args.length == 0)
		{
			return ExecStatus.noCommandGiven;
		}

		string comName = args[0];
		string rawArgs = stripped[args[0].length..$];

		//infof("%s %s> %s", executorName, sourceType, stripped);

		commandTextOutput.put(executorName);
		commandTextOutput.put(">");
		commandTextOutput.putln(stripped);

		if (auto command = comName in commandMap)
		{
			try
			{
				command.handler(CommandParams(rawArgs, args, source, sourceType, &commandTextOutput));
			}
			catch(Exception e)
			{
				commandTextOutput.putf("Error executing command '%s': %s", stripped, e.msg);
				return ExecStatus.error;
			}
		}
		else
		{
			static if(isServer)
			{
				commandTextOutput.putf("Unknown command '%s'", comName);
				return ExecStatus.notRegistered;
			}
			else
			{
				if (connection.isConnected)
				{
					// Redirect unknown command to the server.
					// Server will send response with corresponding endpoint, so results are shown in the right console
					connection.send(CommandPacket(stripped, sourceType));

					// Prevent extra output of typed command, since it will be printed when results come back
					commandTextOutput.clear;

					return ExecStatus.notRegisteredRedirected;
				}
				else
				{
					commandTextOutput.putf("Unknown command '%s', no server connection for redirect", stripped);
					return ExecStatus.notRegistered;
				}
			}
		}

		return ExecStatus.success;
	}
}
