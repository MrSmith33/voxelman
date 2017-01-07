/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module enginestarter;

import std.file : mkdirRecurse;
import std.path : buildPath;
import std.getopt;
import core.thread : Thread, thread_joinAll;
import voxelman.log;
import pluginlib;
import pluginlib.plugininforeader : filterEnabledPlugins;
import pluginlib.pluginmanager;

import voxelman.cons;
import test.cons;


struct EngineStarter
{
	enum AppType { client, server, combined }

	void start(string[] args)
	{
		AppType appType;
		std.getopt.getopt(args,
			std.getopt.config.passThrough,
			std.getopt.config.required,
			"app", &appType);

		setupLogs(appType);
		scope(exit) closeBinLog();

		final switch(appType) with(AppType)
		{
			case client: startClient(args); break;
			case server: startServer(args, ServerMode.standalone); break;
			case combined: startCombined(args); break;
		}

		waitForThreads();
	}

	void setupLogs(AppType appType, string logsFolder = "../logs")
	{
		mkdirRecurse(logsFolder);
		enum textFormat = ".log";
		enum binFormat = ".bin";

		string name;
		final switch(appType) with(AppType)
		{
			case client: name = "client"; break;
			case server: name = "server"; break;
			case combined: name = "client"; break;
		}
		setupLogger(buildPath(logsFolder, name ~ textFormat));
		initBinLog(buildPath(logsFolder, name ~ binFormat));
	}

	void startServer(string[] args, ServerMode serverMode)
	{
		auto pluginman = new PluginManager;
		foreach(p; pluginRegistry.serverPlugins.byValue.filterEnabledPlugins(args))
			pluginman.registerPlugin(p);
		pluginman.initPlugins();
		pluginRegistry.serverMain(args, serverMode);
	}

	void startClient(string[] args)
	{
		auto pluginman = new PluginManager;
		foreach(p; pluginRegistry.clientPlugins.byValue.filterEnabledPlugins(args))
			pluginman.registerPlugin(p);
		pluginman.initPlugins();
		pluginRegistry.clientMain(args);
	}

	void startCombined(string[] args)
	{
		import voxelman.client.servercontrol : stopServer;

		void exec()
		{
			infof("Server thread: %s", Thread.getThis.id);
			try {
				startServer(args, ServerMode.internal);
			} catch(Throwable t) {
				criticalf("Server failed with error");
				criticalf("%s", t.msg);
				criticalf("%s", t);
			}
		}

		Thread serverThread = new Thread(&exec);
		serverThread.start();

		infof("Client thread: %s", Thread.getThis.id);
		startClient(args);
		stopServer();
	}

	void waitForThreads()
	{
		thread_joinAll();
		infof("[Stopped]");
	}
}
