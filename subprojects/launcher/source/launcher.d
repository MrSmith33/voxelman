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

enum JobType
{
	compile,
	run
}

struct JobParams
{
	string pluginPack = "default";
	AppType appType = AppType.client;
	bool startAfterCompile = true;
	bool arch64 = true;
	bool nodeps = true;
	bool force = false;
	JobType jobType;
}

struct Job
{
	JobParams params;
	string command;
	AppLog log;
	ProcessPipes pipes;

	bool isRunning;
	bool needsClose;
	bool needsRestart;
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

	Job*[] jobs;
	size_t numRunningJobs;
	AppLog appLog;

	void startJob(JobParams params = JobParams.init)
	{
		auto job = new Job(params);
		restartJob(job);
		jobs ~= job;
	}

	void restartJob(Job* job)
	{
		assert(!job.isRunning);
		++numRunningJobs;

		string command;
		string workDir;
		if (job.params.jobType == JobType.compile) {
			command = makeCompileCommand(job.params);
			workDir = "";
		}
		else if (job.params.jobType == JobType.run) {
			command = makeRunCommand(job.params);
			workDir = buildFolder;
		}

		//infof("%s", command);

		ProcessPipes pipes = pipeShell(command, Redirect.all, null, Config.none, workDir);

		(*job) = Job(job.params, command, job.log, pipes);
		job.isRunning = true;
	}

	string makeCompileCommand(JobParams params)
	{
		immutable arch = params.arch64 ? `--arch=x86_64` : `--arch=x86`;
		immutable conf = params.appType == AppType.client ? `--config=client` : `--config=server`;
		immutable deps = params.nodeps ? `--nodeps` : ``;
		immutable doForce = params.force ? `--force` : ``;
		return format("dub build -q %s %s %s %s\0", arch, conf, deps, doForce);
	}

	string makeRunCommand(JobParams params)
	{
		string conf = params.appType == AppType.client ? `client.exe` : `server.exe`;
		return format("%s --pack=%s\0", conf, params.pluginPack);
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

					if (job.status == 0)
					{
						if (job.params.jobType == JobType.compile)
						{
							if (job.params.startAfterCompile)
							{
								job.params.jobType = JobType.run;
								job.needsClose = false;
								job.log.clear();
								restartJob(job);
							}
							else
								job.needsClose = true;
						}
						else if (job.params.jobType == JobType.run)
						{
							if (job.status == 0)
								job.needsClose = true;
						}
					}
					else
						job.needsClose = false;
				}
			}

			if (!job.isRunning && job.needsRestart)
			{
				job.params.jobType = JobType.compile;
				job.log.clear();
				restartJob(job);
			}
		}

		jobs = remove!(a => a.needsClose && !a.isRunning)(jobs);
	}

	void logPipes(J)(J job)
	{
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
					job.log.addLog(data);
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
				pluginPacks ~= pack;
				pluginsPacksById[pack.id] = pack;
			}
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
