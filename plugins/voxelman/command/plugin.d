module voxelman.command.plugin;

import pluginlib;
public import netlib.connection : ClientId;
public import std.getopt;

shared static this()
{
	pluginRegistry.regClientPlugin(new CommandPlugin);
	pluginRegistry.regServerPlugin(new CommandPlugin);
}

// On client side source == thisClientId
// On server if command is issued locally source == 0
// First argument is command name (useful for std.getopt)
alias CommandHandler = void delegate(string[] args, ClientId source);

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

	ExecResult execute(string input, ClientId source = ClientId(0))
	{
		import std.regex : ctRegex, splitter;
		import std.string : strip;
		import std.array : array;

		string stripped = input.strip;
		string[] args = splitter(stripped, ctRegex!`\s+`).array;

		if (args.length == 0)
			return ExecResult(args, ExecStatus.notRegistered);

		string comName = args[0];

		if (auto handler = handlers.get(comName, null))
		{
			try
			{
				handler(args, source);
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
