/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module main;

import gui;
import launcher;
import std.getopt;

void main(string[] args)
{
	uint releaseBuild;
	Compiler compiler;

	getopt(
		args,
		"release", &releaseBuild,
		"compiler", &compiler);

	if (releaseBuild == 32 || releaseBuild == 64)
	{
		import launcher;
		import std.process;
		import std.stdio;
		JobParams params;
		params.arch64 = releaseBuild == 64 ? Yes.arch64 : No.arch64;
		params.nodeps = Yes.nodeps;
		params.force = No.force;
		params.release = Yes.release;
		params.compiler = compiler;

		string comBuild = makeCompileCommand(params);
		writefln("Building voxelman %sbit '%s'", releaseBuild, comBuild);
		executeShell(comBuild);
	}
	else
	{
		LauncherGui app;
		app.run();
	}
}
