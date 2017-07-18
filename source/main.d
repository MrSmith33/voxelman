/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module main;

void main(string[] args)
{
	import cons : register;
	import pluginlib.pluginregistry : pluginRegistry;
	register(pluginRegistry);

	version(unittest)
	{}
	else
	{
		import enginestarter : EngineStarter;
		EngineStarter engineStarter;
		engineStarter.start(args);
	}
}
