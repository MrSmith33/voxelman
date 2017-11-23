/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module pluginlib.plugininforeader;

import voxelman.log;
import pluginlib;

enum pluguinPackFolder = `../../pluginpacks`;

auto filterEnabledPlugins(Plugins)(Plugins plugins, ref string[] args)
{
	import std.getopt;
	import std.file;
	import std.range;
	import std.algorithm;
	import std.string : format;

	string packName;
	string packId;

	auto helpInformation = getopt(args,
		std.getopt.config.passThrough,
	    "pack",  &packId);

	if (packId.length == 0)
		packId = "default";

	packName = format("%s/%s.txt", pluguinPackFolder, packId);

	PluginInfo*[string] packPlugins;
	if (exists(packName))
	{
		string fileData = cast(string)read(packName);
		PluginPack* pack = readPluginPack(fileData);
		foreach(plug; pack.plugins)
			packPlugins[plug.id] = plug;
		infof("Found %s plugins in '%s' pack", packPlugins.length, pack.id);
	}
	else
		infof("Cannot load: %s", packName);

	return plugins.filter!(p => p.id in packPlugins);
}

struct PluginInfo
{
	string id;
	string semver;
	string downloadUrl;
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

PluginInfo* readPluginInfo(string fileData)
{
	import std.regex : matchFirst, regex;

	auto pinfo = new PluginInfo;

	auto idCapture = matchFirst(fileData, regex(`id\s*=\s*"(?P<id>[^"]*)"`, "s"));
	pinfo.id = idCapture["id"].idup;

	auto semverCapture = matchFirst(fileData, regex(`semver\s*=\s*"(?P<semver>[^"]*)"`, "s"));
	pinfo.semver = semverCapture["semver"].idup;

	return pinfo;
}

PluginPack* readPluginPack(string fileData)
{
	import std.algorithm : startsWith;
	import std.array : empty;
	import std.regex : matchFirst, regex;
	import std.string : lineSplitter;

	auto pack = new PluginPack;

	auto input = fileData.lineSplitter;

	if (!input.empty) {
		auto packInfo = matchFirst(input.front, regex(`(?P<id>[^\s]*)\s+(?P<semver>.*)`, "m"));
		pack.id = packInfo["id"].idup;
		pack.semver = packInfo["semver"].idup;
		input.popFront;
	}

	foreach(line; input)
	{
		if (line.empty || startsWith(line, "#"))
			continue;

		auto pluginInfo = matchFirst(line, regex(`(?P<id>[^\s]*)\s+(?P<semver>.*)`, "m"));
		auto pinfo = new PluginInfo;
		pinfo.id = pluginInfo["id"].idup;
		pinfo.semver = pluginInfo["semver"].idup;
		pack.plugins ~= pinfo;
	}

	return pack;
}
