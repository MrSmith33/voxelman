/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module main;

import enginestarter;

void main(string[] args)
{
	version(unittest)
	{}
	else
	{
		EngineStarter engineStarter;
		engineStarter.start(args);
	}
}
