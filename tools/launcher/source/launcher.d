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
public import std.typecons : Flag, Yes, No;
import std.file;
import std.path;
import std.conv : to;

import voxelman.utils.messagewindow;
import voxelman.utils.linebuffer;
import gui;

enum DEFAULT_PORT = 1234;

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
	compileAndRun,
	test
}

enum JobState
{
	build,
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
	string[string] runParameters;
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

	JobState jobState = JobState.build;
	string title;
	bool isRunning;
	bool needsClose;
	bool needsRestart;
	int status;
}

string jobStateString(Job* job)
{
	if (!job.isRunning) return "[STOPPED]";
	final switch(job.jobState) with(JobState)
	{
		case build: break;
		case run: return "[RUNNING]";
	}

	final switch(job.params.jobType) with(JobType)
	{
		case run: return "[INVALID]";
		case compile: return "[BUILDING]";
		case compileAndRun: return "[BUILDING]";
		case test: return "[TESTING]";
	}
	assert(false);
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

	void createJob(JobParams params = JobParams.init)
	{
		auto job = new Job(params);
		job.messageWindow.init();
		job.messageWindow.messageHandler = (string com)=>sendCommand(job,com);
		updateJobType(job);
		restartJobState(job);
		updateTitle(job);
		jobs ~= job;
	}

	static void updateTitle(Job* job)
	{
		string title = job.params.appType == AppType.client ? `Client` : `Server`;
		job.title = title;
	}

	static void updateJobType(Job* job)
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
			case test:
				job.params.build = Yes.build;
				job.params.start = No.start;
				break;
		}
	}

	static void restartJobState(Job* job)
	{
		final switch(job.params.jobType) with(JobType) {
			case run: job.jobState = JobState.run; break;
			case compile: job.jobState = JobState.build; break;
			case compileAndRun: job.jobState = JobState.build; break;
			case test: job.jobState = JobState.build; break;
		}
	}

	void startJob(Job* job)
	{
		assert(!job.isRunning);
		++numRunningJobs;

		updateJobType(job);
		updateTitle(job);

		string command;
		string workDir;

		if (job.jobState == JobState.build)
		{
			final switch(job.params.jobType) with(JobType) {
				case run: return;
				case compile: goto case;
				case compileAndRun:
					command = makeCompileCommand(job.params);
					workDir = "";
					break;
				case test:
					command = makeTestCommand(job.params);
					workDir = "";
					break;
			}
		}
		else if (job.jobState == JobState.run) {
			command = makeRunCommand(job.params);
			workDir = buildFolder;
		}

		ProcessPipes pipes = pipeShell(command, Redirect.all, null, Config.none, workDir);

		(*job) = Job(job.params, command, job.messageWindow, pipes, job.jobState, job.title);
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
					bool doneBuild = job.jobState == JobState.build;
					bool needsStart = job.params.start;
					if (doneBuild)
					{
						onJobBuildCompletion(job, job.status == 0);
					}
					if (success && doneBuild && needsStart)
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

	void addServer(ServerInfo server)
	{
		auto info = new ServerInfo();
		*info = server;
		servers ~= info;
		saveServers();
	}

	void removeServer(size_t serverIndex)
	{
		servers = remove(servers, serverIndex);
		saveServers();
	}

	void saveServers()
	{
		import std.exception;
		try
		{
			auto f = File(serversFname, "w");
			foreach(server; servers)
			{
				f.writefln("%s:%s %s", server.ip, server.port, server.name);
			}
		}
		catch(ErrnoException e)
		{
			error(e);
		}
	}
}

string makeCompileCommand(JobParams params)
{
	immutable arch = params.arch64 ? `--arch=x86_64` : `--arch=x86`;
	immutable deps = params.nodeps ? ` --nodeps` : ``;
	immutable doForce = params.force ? ` --force` : ``;
	immutable release = params.release ? `--build=release` : `--build=debug`;
	immutable compiler = format(`--compiler=%s`, compilerExeNames[params.compiler]);
	return format("dub build -q %s %s --config=exe%s%s %s\0", arch, compiler, deps, doForce, release)[0..$-1];
}

string makeRunCommand(JobParams params)
{
	string conf = params.appType == AppType.client ? `voxelman.exe --app=client` : `voxelman.exe --app=server`;
	string command = conf;

	foreach(paramName, paramValue; params.runParameters)
	{
		if (paramValue)
			command ~= format(" --%s=%s", paramName, paramValue);
		else
			command ~= format(" --%s", paramName);
	}

	command ~= '\0';
	return command[0..$-1];
}

string makeTestCommand(JobParams params)
{
	immutable arch = params.arch64 ? `--arch=x86_64` : `--arch=x86`;
	immutable deps = params.nodeps ? ` --nodeps` : ``;
	immutable doForce = params.force ? ` --force` : ``;
	immutable compiler = format(`--compiler=%s`, compilerExeNames[params.compiler]);
	return format("dub test -q %s %s %s %s\0", arch, compiler, deps, doForce)[0..$-1];
}

void onJobBuildCompletion(Job* job, bool success)
{
	if (success)
	{
		if (job.params.jobType != JobType.test)
			job.messageWindow.putln("Compilation successful");
	}
	else
	{
		if (job.params.jobType != JobType.test)
			job.messageWindow.putln("Compilation failed");
	}
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
	if (!job.isRunning) return;

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
	copy[s.length] = '\0';
	return assumeUnique(copy[0..s.length]);
}

string fromCString(char[] str)
{
	char[] chars = str.ptr.fromStringz();
	return chars.ptr[0..chars.length+1].idup[0..$-1];
}
