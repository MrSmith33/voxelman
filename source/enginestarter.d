/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module enginestarter;

import std.file : mkdirRecurse, getcwd;
import std.path : buildPath;
import std.getopt;
import core.thread : Thread, thread_joinAll;
import voxelman.log;
import pluginlib;
import pluginlib.plugininforeader : filterEnabledPlugins;
import pluginlib.pluginmanager;


struct EngineStarter
{
	enum AppType { client, server, combined }

	void start(string[] args)
	{
		AppType appType = AppType.combined;
		bool logToConsole;
		std.getopt.getopt(args,
			std.getopt.config.passThrough,
			"app", &appType,
			"console_log", &logToConsole);

		setupLogs(appType, logToConsole);
		scope(exit) closeBinLog();

		infof("Started from '%s'", getcwd);

		final switch(appType) with(AppType)
		{
			case client: startClient(args); break;
			case server: startServer(args, ServerMode.standalone); break;
			case combined: startCombined(args); break;
		}

		waitForThreads();
	}

	void setupLogs(AppType appType, bool logToConsole = true, string logsFolder = "../logs")
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

		auto logger = setupMultiLogger();
		setupFileLogger(logger, buildPath(logsFolder, name ~ textFormat));
		if (logToConsole)
			setupStdoutLogger(logger);

		initBinLog(buildPath(logsFolder, name ~ binFormat));
	}

	void startServer(string[] args, ServerMode serverMode)
	{
		infof("Server thread: %s", Thread.getThis.id);
		try {
			auto pluginman = new PluginManager;
			foreach(p; pluginRegistry.serverPlugins.byValue.filterEnabledPlugins(args))
				pluginman.registerPlugin(p);
			pluginman.initPlugins();
			pluginRegistry.serverMain(args, serverMode);
		} catch(Throwable t) {
			criticalf("Server failed with error");
			criticalf("%s", t.msg);
			criticalf("%s", t);
		}
	}

	void startClient(string[] args)
	{
		infof("Client thread: %s", Thread.getThis.id);
		try {
			auto pluginman = new PluginManager;
			foreach(p; pluginRegistry.clientPlugins.byValue.filterEnabledPlugins(args))
				pluginman.registerPlugin(p);
			pluginman.initPlugins();
			pluginRegistry.clientMain(args);
		} catch(Throwable t) {
			criticalf("Client failed with error");
			criticalf("%s", t.msg);
			criticalf("%s", t);
		}
	}

	void startCombined(string[] args)
	{
		import voxelman.thread.servercontrol : stopServer;

		void exec()
		{
			startServer(args, ServerMode.internal);
		}

		Thread serverThread = new Thread(&exec);
		serverThread.start();

		startClient(args);
		stopServer();
	}

	void waitForThreads()
	{
		thread_joinAll();
		infof("[Stopped]");
	}
}
