/**
Copyright: Copyright (c) 2015-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.config.configmanager;

import voxelman.log;
import std.file : read, exists;
public import std.variant;
import std.traits : isArray;
import std.conv : to;

import pluginlib;
import sdlang;

alias ConfigValue = Algebraic!(int, double, string, bool, int[], double[]);

final class ConfigOption
{
	this(ConfigValue value, ConfigValue defaultValue)
	{
		this.value = value;
		this.defaultValue = defaultValue;
	}

	T get(T)()
	{
		static if (isArray!T)
			return value.get!T();
		else
			return value.coerce!T();
	}

	T set(T)(T newValue)
	{
		value = newValue;
		return newValue;
	}

	ConfigValue value;
	ConfigValue defaultValue;
}

final class ConfigManager : IResourceManager
{
private:
	ConfigOption[string] options;
	string filename;
	string[] args;

public:

	override string id() @property { return "voxelman.managers.configmanager"; }

	this(string filename, string[] args)
	{
		this.filename = filename;
		this.args = args;
	}

	override void loadResources()
	{
		load();
	}

	// Runtime options are not saved. Use them to store global options that need no saving
	ConfigOption registerOption(T)(string optionName, T defaultValue)
	{
		if (auto opt = optionName in options)
			return *opt;
		auto option = new ConfigOption(ConfigValue(defaultValue), ConfigValue(defaultValue));
		options[optionName] = option;
		return option;
	}

	ConfigOption opIndex(string optionName)
	{
		return options.get(optionName, null);
	}

	void load()
	{
		bool readConfigFile = exists(filename);
		Tag root;

		if (readConfigFile)
		try
		{
			string fileData = cast(string)read(filename);
			root = parseSource(fileData, filename);
		}
		catch(SDLangParseException e)
		{
			warning(e.msg);
			return;
		}

		auto tempSep = std.getopt.arraySep;
		std.getopt.arraySep = ",";
		foreach(optionPair; options.byKeyValue)
		{
			if (readConfigFile)
			{
				parseValueFromConfig(optionPair.key, optionPair.value, root);
			}

			// override from console
			parseValueFromCmd(optionPair.key, optionPair.value, args);
		}
		std.getopt.arraySep = tempSep;
	}

	void save() {}

private:

	static void parseValueFromConfig(string optionName, ConfigOption option, Tag root)
	{
		if (optionName !in root.tags) return;
		auto tags = root.tags[optionName];

		if (tags.length == 1)
		{
			try
			{
				parseValue(optionName, option, tags[0].values);
				//infof("%s %s %s", optionName, option.value, option.defaultValue);
			}
			catch(VariantException e)
			{
				warningf("Error parsing config option: %s - %s", optionName, e.msg);
			}
		}
		else if (tags.length > 1)
			warningf("Multiple definitions of '%s'", optionName);
		else
			warningf("Empty option '%s'", optionName);
	}

	static void parseValue(string optionName, ConfigOption option, Value[] values)
	{
		if (values.length == 1)
		{
			Value value = values[0];

			if (option.value.type == typeid(bool)) {
				option.value = ConfigValue(value.coerce!bool);
			}
			else if (option.value.type == typeid(string)) {
				option.value = ConfigValue(value.coerce!string);
			}
			else if (option.value.type == typeid(int)) {
				option.value = ConfigValue(value.coerce!int);
			}
			else if (option.value.type == typeid(double)) {
				option.value = ConfigValue(value.coerce!double);
			}
			else
			{
				warningf("Cannot parse '%s' from '%s'", optionName, value.to!string);
			}
		}
		else if (values.length > 1)
		{
			void parseArray(T)()
			{
				T[] items;
				foreach(v; values)
					items ~= v.coerce!T;
				option.value = ConfigValue(items);
			}
			if (option.value.length != values.length)
				return;

			if (option.value.type == typeid(int[])) {
				parseArray!int;
			} else if (option.value.type == typeid(double[])) {
				parseArray!double;
			} else {
				warningf("Cannot parse '%s' from '%s'", optionName, values.to!string);
			}
			//infof("conf %s %s", optionName, option.value);
		}
	}

	static void parseValueFromCmd(string optionName, ConfigOption option, string[] args)
	{
		if (option.value.type == typeid(int)) {
			parseSingle!int(optionName, option, args);
		}
		else if (option.value.type == typeid(double)) {
			parseSingle!double(optionName, option, args);
		}
		else if (option.value.type == typeid(string)) {
			parseSingle!string(optionName, option, args);
		}
		else if (option.value.type == typeid(bool)) {
			parseSingle!bool(optionName, option, args);
		}
		else if (option.value.type == typeid(int[])) {
			parseSingle!(int[])(optionName, option, args);
		}
		else if (option.value.type == typeid(double[])) {
			parseSingle!(double[])(optionName, option, args);
		}
	}
}

import std.getopt;
void parseSingle(T)(string optionName, ConfigOption option, string[] args)
{
	T val = option.get!T;
	//infof("cmd1 %s %s", optionName, val);

	static if(is(T == int[]) || is(T == double[]))
	{
		T newArray;
		auto res = getopt(args, std.getopt.config.passThrough, optionName, &newArray);
		if (newArray != newArray.init)
			val = newArray;
	}
	else
	{
		getopt(args, std.getopt.config.passThrough, optionName, &val);
	}
	//infof("cmd2 %s %s", optionName, val);

	option.value = ConfigValue(val);
}
