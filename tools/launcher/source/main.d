/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module main;

import gui;
import launcher;
import std.getopt;
import std.algorithm : countUntil;

void main(string[] args)
{
	uint arch;
	Compiler compiler;
	string buildType;

	getopt(
		args,
		"arch", &arch,
		"compiler", &compiler,
		"build", &buildType);

	if (arch == 32 || arch == 64)
	{
		setupLoggers(true);

		import launcher;
		import std.process;
		import std.stdio;
		JobParams params;
		params.arch64 = arch == 64 ? Yes.arch64 : No.arch64;
		params.nodeps = Yes.nodeps;
		params.force = No.force;
		params.buildType = BuildType.bt_release;
		if (buildType)
		{
			ptrdiff_t index = countUntil(buildTypeSwitches, buildType);
			if (index != -1)
			{
				params.buildType = cast(BuildType)index;
			}
		}
		params.compiler = compiler;

		string comBuild = makeBuildOrTestCommand(params);
		writefln("Building voxelman %sbit '%s'", arch, comBuild);
		executeShell(comBuild);
	}
	else
	{
		setupLoggers(false);
		LauncherGui app;
		app.run();
	}
}

void setupLoggers(bool logToConsole)
{
	import voxelman.log;
	auto logger = setupMultiLogger();
	if (logToConsole)
		setupStdoutLogger(logger);
}
