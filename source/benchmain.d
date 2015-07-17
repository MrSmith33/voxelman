/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.benchmain;

import std.experimental.logger;
import std.file : mkdirRecurse;

import voxelman.utils.log;

void main(string[] args)
{
	mkdirRecurse("../logs");
	setupLogger("../logs/bench.log");
	info("benchmarking");
}
