/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.command.plugin;

import pluginlib;
public import netlib.connection : ClientId;
public import std.getopt;

shared static this()
{
	pluginRegistry.regClientPlugin(new CommandPlugin);
	pluginRegistry.regServerPlugin(new CommandPlugin);
}

struct CommandParams
{
	string rawArgs; // without command name
	string[] args; // first arg is command name
	ClientId source;
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

final class CommandPlugin : IPlugin
{
	// IPlugin stuff
	mixin IdAndSemverFrom!(voxelman.command.plugininfo);

	CommandHandler[string] handlers;

	void registerCommand(string name, CommandHandler handler)
	{
		assert(name !in handlers, name ~ " command is already registered");
		handlers[name] = handler;
	}

	ExecResult execute(const(char)[] input, ClientId source = ClientId(0))
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
