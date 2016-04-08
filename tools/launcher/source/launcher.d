/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
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
import std.typecons : Flag, Yes, No;
import std.file;
import std.path;
import std.conv : to;

import voxelman.utils.messagewindow;
import voxelman.utils.linebuffer;
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

enum JobType : int
{
	run,
	compile,
	compileAndRun
}

enum JobState
{
	compile,
	run
}

enum Compiler
{
	dmd,
	ldc,
	gdc
}

string[] compilerExeNames = ["dmd", "ldc2", "gdc"];

struct JobParams
{
	string pluginPack = "default";
	AppType appType = AppType.client;
	Flag!"start" start = Yes.start;
	Flag!"build" build = Yes.build;
	Flag!"arch64" arch64 = Yes.arch64;
	Flag!"nodeps" nodeps = Yes.nodeps;
	Flag!"force" force = No.force;
	Flag!"release" release = No.release;
	Compiler compiler;
	JobType jobType;
}

struct Job
{
	JobParams params;
	string command;
	MessageWindow messageWindow;
	ProcessPipes pipes;

	JobState jobState = JobState.compile;
	bool isRunning;
	bool needsClose;
	bool needsRestart;
	int status;
}

struct ServerInfo
{
	string name;
	string ip;
	ushort port;
}

immutable buildFolder = "builds/default";
immutable configFolder = "config";
immutable serversFname = "config/servers.txt";
struct Launcher
{
	string pluginFolderPath;
	string pluginPackFolderPath;
	PluginInfo*[] plugins;
	PluginInfo*[string] pluginsById;
	PluginPack*[] pluginPacks;
	PluginPack*[string] pluginsPacksById;
	ServerInfo*[] servers;

	Job*[] jobs;
	size_t numRunningJobs;
	LineBuffer appLog;

	void setupJob(JobParams params = JobParams.init)
	{
		auto job = new Job(params);
		job.messageWindow.init();
		job.messageWindow.messageHandler = (string com)=>sendCommand(job,com);
		updateJobType(job);
		restartJobState(job);
		startJob(job);
		jobs ~= job;
	}

	void updateJobType(Job* job)
	{
		final switch(job.params.jobType) with(JobType) {
			case run:
				job.params.build = No.build;
				job.params.start = Yes.start;
				break;
			case compile:
				job.params.build = Yes.build;
				job.params.start = No.start;
				break;
			case compileAndRun:
				job.params.build = Yes.build;
				job.params.start = Yes.start;
				break;
		}
	}

	void restartJobState(Job* job)
	{
		final switch(job.params.jobType) with(JobType) {
			case run: job.jobState = JobState.run; break;
			case compile: job.jobState = JobState.compile; break;
			case compileAndRun: job.jobState = JobState.compile; break;
		}
	}

	void startJob(Job* job)
	{
		assert(!job.isRunning);
		++numRunningJobs;

		string command;
		string workDir;
		if (job.jobState == JobState.compile) {
			command = makeCompileCommand(job.params);
			writeln(command);
			workDir = "";
		}
		else if (job.jobState == JobState.run) {
			command = makeRunCommand(job.params);
			workDir = buildFolder;
		}

		ProcessPipes pipes = pipeShell(command, Redirect.all, null, Config.none, workDir);

		(*job) = Job(job.params, command, job.messageWindow, pipes, job.jobState);
		job.isRunning = true;
	}

	size_t stopProcesses()
	{
		foreach(job; jobs)
			job.pipes.pid.kill;
		return jobs.length;
	}

	bool anyProcessesRunning() @property
	{
		return numRunningJobs > 0;
	}

	void update()
	{
		foreach(job; jobs) logPipes(job);

		foreach(job; jobs)
		{
			if (job.isRunning)
			{
				auto res = job.pipes.pid.tryWait();
				if (res.terminated)
				{
					--numRunningJobs;
					job.isRunning = false;
					job.status = res.status;

					bool success = job.status == 0;
					bool doneCompilation = job.jobState == JobState.compile;
					bool needsStart = job.params.start;
					if (doneCompilation)
						job.messageWindow.putln(job.status == 0 ? "Compilation successful" : "Compilation failed");
					if (success && doneCompilation && needsStart)
					{
						job.jobState = JobState.run;
						startJob(job);
					}
				}
			}

			if (!job.isRunning && job.needsRestart)
			{
				job.messageWindow.lineBuffer.clear();
				restartJobState(job);
				startJob(job);
			}

			job.needsRestart = false;
		}

		jobs = remove!(a => a.needsClose && !a.isRunning)(jobs);
		jobs.each!(j => j.needsClose = false);
	}

	void setRootPath(string pluginFolder, string pluginPackFolder, string toolFolder)
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
		if (!exists(pluginFolderPath)) return;
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

	void readPluginPacks()
	{
		foreach (entry; dirEntries(pluginPackFolderPath, SpanMode.depth))
		{
			if (entry.isFile && entry.name.extension == ".txt")
			{
				string fileData = cast(string)read(entry.name);
				auto pack = readPluginPack(fileData);
				pack.filename = entry.name.absolutePath.buildNormalizedPath;
				pluginPacks ~= pack;
				pluginsPacksById[pack.id] = pack;
			}
		}
	}

	void readServers()
	{
		import std.regex : matchFirst, ctRegex;
		if (!exists(serversFname)) return;
		string serversData = cast(string)read(serversFname);
		foreach(line; serversData.lineSplitter)
		{
			auto serverInfoStr = matchFirst(line, ctRegex!(`(?P<ip>[^:]*):(?P<port>\d{1,5})\s*(?P<name>.*)`, "s"));
			auto sinfo = new ServerInfo;
			sinfo.ip = serverInfoStr["ip"].toCString;
			sinfo.port = to!ushort(serverInfoStr["port"]);
			sinfo.name = serverInfoStr["name"].toCString;
			infof("%s", *sinfo);
			servers ~= sinfo;
		}
	}
}

string makeCompileCommand(JobParams params)
{
	immutable arch = params.arch64 ? `--arch=x86_64` : `--arch=x86`;
	immutable conf = params.appType == AppType.client ? `--config=client` : `--config=server`;
	immutable deps = params.nodeps ? ` --nodeps` : ``;
	immutable doForce = params.force ? ` --force` : ``;
	immutable release = params.release ? `--build=release` : `--build=debug`;
	immutable compiler = format(`--compiler=%s`, compilerExeNames[params.compiler]);
	return format("dub build -q %s %s %s%s%s %s\0", arch, compiler, conf, deps, doForce, release);
}

string makeRunCommand(JobParams params)
{
	string conf = params.appType == AppType.client ? `client.exe` : `server.exe`;
	return format("%s --pack=%s\0", conf, params.pluginPack);
}

void sendCommand(Job* job, string command)
{
	if (!job.isRunning) return;
	job.pipes.stdin.rawWrite(command);
	job.pipes.stdin.rawWrite("\n");
}

void logPipes(Job* job)
{
	import std.exception : ErrnoException;
	import std.utf : UTFException;
	try
	{
		foreach(pipe; only(job.pipes.stdout, job.pipes.stderr))
		{
			auto size = pipe.size;
			if (size > 0)
			{
				char[1024] buf;
				size_t charsToRead = min(pipe.size, buf.length);
				char[] data = pipe.rawRead(buf[0..charsToRead]);
				job.messageWindow.lineBuffer.put(data);
			}
		}
	}
	catch(ErrnoException e)
	{	// Ignore e
		// It happens only when both launcher and child process is 32bit
		// and child crashes with access violation (in opengl call for example).
		// exception std.exception.ErrnoException@std\stdio.d(920):
		// Could not seek in file `HANDLE(32C)' (Invalid argument)
	}
	catch(UTFException e)
	{	// Ignore e
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
