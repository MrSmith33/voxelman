/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module launcher;

import std.experimental.logger;
import std.process;
import std.string;
import std.algorithm;
import std.stdio;
import std.array;
import std.range;
//import derelict.imgui.imgui;

import gui;

struct PluginInfo
{
	string id;
	string semver;
	string downloadUrl;
	bool isEnabled = true;
	PluginInfo*[] dependencies;
	PluginInfo*[] dependants;
}

struct PluginPack
{
	string id;
	string semver;
	string filename;
	PluginInfo*[] plugins;
}

enum AppType
{
	client,
	server
}

struct CompileParams
{
	AppType appType = AppType.client;
	bool startAfterCompile = true;
	bool arch64 = true;
	bool nodeps = true;
}

struct StartParams
{
	string pluginPack = "default";
	AppType appType = AppType.client;
}

struct CompileJob
{
	ProcessPipes pipes;

	CompileParams cParams;
	StartParams sParams;

	string command;
	bool isRunning = true;
	bool needsClose = false;
	AppLog log;
	int status;
}

struct RunJob
{
	ProcessPipes pipes;

	StartParams params;

	string command;
	bool isRunning = true;
	bool needsClose = false;
	AppLog log;
	int status;
}

immutable buildFolder = "builds/default";
struct Launcher
{
	string pluginFolderPath;
	string pluginPackFolderPath;
	PluginInfo*[] plugins;
	PluginInfo*[string] pluginsById;
	PluginPack*[] pluginPacks;
	PluginPack*[string] pluginsPacksById;

	CompileJob*[] compileJobs;
	RunJob*[] runJobs;
	size_t numRunningJobs;
	AppLog appLog;

	void compile(CompileParams cParams = CompileParams.init,
		StartParams sParams = StartParams.init)
	{
		++numRunningJobs;
		//infof("+1 %s", numRunningJobs);
		immutable arch = cParams.arch64 ? `--arch=x86_64`   : `--arch=x86`;
		immutable conf = cParams.appType == AppType.client ? `--config=client` : `--config=server`;
		immutable deps = cParams.nodeps ? `--nodeps`        : ``;
		//immutable cmnd = cParams.startAfterCompile ? "run" : "build";
		immutable command = format("dub build -q %s %s %s\0", arch, conf, deps);
		ProcessPipes pipes = pipeShell(command, Redirect.all, null);
		sParams.appType = cParams.appType;
		compileJobs ~= new CompileJob(pipes, cParams, sParams, command);
	}

	void startApp(StartParams params = StartParams.init, AppLog log = AppLog.init)
	{
		++numRunningJobs;
		//infof("+2 %s", numRunningJobs);
		string conf = params.appType == AppType.client ? `client.exe` : `server.exe`;
		//info(format("  starting with pack %s", params.pluginPack));
		string command = format("%s --pack=%s\0", conf, params.pluginPack);
		infof(command);
		ProcessPipes pipes = pipeShell(command, Redirect.all, null, Config.none, buildFolder);
		auto job = new RunJob(pipes, params, command);
		job.log = log;
		job.log.addLog(format("starting with pack %s\n", params.pluginPack));
		runJobs ~= job;
	}

	size_t stopProcesses()
	{
		foreach(process; runJobs)
			process.pipes.pid.kill;
		foreach(process; compileJobs)
			process.pipes.pid.kill;
		size_t numProcesses = runJobs.length + compileJobs.length;
		return numProcesses;
	}

	bool anyProcessesRunning() @property
	{
		return numRunningJobs > 0;
	}

	void update()
	{
		foreach(process; compileJobs) logPipes(process);
		foreach(process; runJobs) logPipes(process);

		foreach(process; runJobs)
		{
			if (process.pipes.pid.tryWait.terminated) {
				--numRunningJobs;
				//infof("-1 %s", numRunningJobs);
				process.isRunning = false;
				process.needsClose = true;
			}
		}

		foreach(process; compileJobs)
		{
			auto res = process.pipes.pid.tryWait();
			if (res.terminated && process.isRunning) {
				process.isRunning = false;
				--numRunningJobs;
				//infof("-2 %s %s", numRunningJobs, process.command);
				process.status = res.status;

				if (process.cParams.startAfterCompile && res.status == 0) {
					startApp(process.sParams, process.log);
					process.needsClose = true;
				}
			}
		}

		runJobs = remove!(a => a.needsClose)(runJobs);
		compileJobs = remove!(a => a.needsClose)(compileJobs);
	}

	void logPipes(J)(J job)
	{
		foreach(ref pipe; only(job.pipes.stdout, job.pipes.stderr))
		if (pipe.size > 0)
		{
			char[1024] buf;
			size_t charsToRead = min(pipe.size, buf.length);
			char[] data = pipe.rawRead(buf[0..charsToRead]);
			job.log.addLog(data);
		}
	}

	void setRootPath(string pluginFolder, string pluginPackFolder)
	{
		pluginFolderPath = pluginFolder;
		pluginPackFolderPath = pluginPackFolder;
	}

	void clear()
	{
		plugins = null;
		pluginsById = null;
		pluginPacks = null;
		pluginsPacksById = null;
	}

	void readPlugins()
	{
		import std.file : read, dirEntries, SpanMode;
		import std.path : baseName;

		foreach (entry; dirEntries(pluginFolderPath, SpanMode.depth))
		{
			if (entry.isFile && baseName(entry.name) == "plugininfo.d")
			{
				string fileData = cast(string)read(entry.name);
				auto p = readPluginInfo(fileData);
				plugins ~= p;
				pluginsById[p.id] = p;
			}
		}
	}

	void printPlugins()
	{
		foreach(p; plugins)
		{
			infof("%s %s", p.id, p.semver);
		}
	}

	void readPluginPacks()
	{
		import std.file : read, dirEntries, SpanMode;
		import std.path : extension, absolutePath, buildNormalizedPath;

		foreach (entry; dirEntries(pluginPackFolderPath, SpanMode.depth))
		{
			if (entry.isFile && entry.name.extension == ".txt")
			{
				string fileData = cast(string)read(entry.name);
				auto pack = readPluginPack(fileData);
				pack.filename = entry.name.absolutePath.buildNormalizedPath;
				//infof(`"%s": "%s", "%s"`, pack.id, pack.semver, pack.filename);
				//foreach(plug; pack.plugins)
				//	infof(`	"%s": "%s"`, plug.id, plug.semver);
				pluginPacks ~= pack;
				pluginsPacksById[pack.id] = pack;
			}
		}
	}

	void addTestPlugins()
	{
		import std.string : format;

		foreach(i; 0..100)
		{
			auto pinfo = new PluginInfo;
			pinfo.id = format("testplugin.%s", i);
			pinfo.semver = format("0.%s.0", i);
			plugins ~= pinfo;
			pluginsById[pinfo.id] = pinfo;
		}
	}
}

PluginInfo* readPluginInfo(string fileData)
{
	import std.regex : matchFirst, ctRegex;

	auto pinfo = new PluginInfo;

	auto idCapture = matchFirst(fileData, ctRegex!(`id\s*=\s*"(?P<id>[^"]*)"`, "s"));
	pinfo.id = idCapture["id"].toCString;

	auto semverCapture = matchFirst(fileData, ctRegex!(`semver\s*=\s*"(?P<semver>[^"]*)"`, "s"));
	pinfo.semver = semverCapture["semver"].toCString;
	//

	return pinfo;
}

PluginPack* readPluginPack(string fileData)
{
	import std.array : empty;
	import std.regex : matchFirst, ctRegex;
	import std.string : lineSplitter;

	auto pack = new PluginPack;

	auto input = fileData.lineSplitter;

	if (!input.empty) {
		auto packInfo = matchFirst(input.front, ctRegex!(`(?P<id>.*) (?P<semver>.*)`, "m"));
		pack.id = packInfo["id"].toCString;
		pack.semver = packInfo["semver"].toCString;
		input.popFront;
	}

	foreach(line; input)
	{
		if (line.empty)
			continue;

		auto pluginInfo = matchFirst(line, ctRegex!(`(?P<id>.*) (?P<semver>.*)`, "m"));
		auto pinfo = new PluginInfo;
		pinfo.id = pluginInfo["id"].toCString;
		pinfo.semver = pluginInfo["semver"].toCString;
		//infof("line %s %s %s", line, pinfo.id, pinfo.semver);
		pack.plugins ~= pinfo;
	}

	return pack;
}

string toCString(in const(char)[] s)
{
    import std.exception : assumeUnique;
    auto copy = new char[s.length + 1];
    copy[0..s.length] = s[];
    copy[s.length] = 0;
    return assumeUnique(copy[0..s.length]);
}
