/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.resourcemanagers.config;

import std.experimental.logger;
import std.file : read, exists;
public import std.variant;
import std.traits : isArray;
import std.conv : to;

import sdlang;
import resource;

final class ConfigOption
{
	this(Variant value, Variant defaultValue, bool isSaved)
	{
		this.value = value;
		this.defaultValue = defaultValue;
		this.isSaved = isSaved;
	}

	T get(T)()
	{
		static if (isArray!T)
			return value.get!T();
		else
			return value.coerce!T();
	}

	Variant value;
	Variant defaultValue;
	bool isSaved;
}

final class Config : IResourceManager
{
private:
	ConfigOption[string] options;
	string filename;

public:

	override string name() @property { return "Config"; }
	override string semver() @property { return "0.5.0"; }

	this(string filename)
	{
		this.filename = filename;
	}

	override void loadResources()
	{
		load();
	}

	// Runtime options are not saved. Use them to store global options that need no saving
	ConfigOption registerOption(T)(string optionName, T defaultValue, bool runtime = false)
	{
		auto option = new ConfigOption(Variant(defaultValue), Variant(defaultValue), runtime);
		options[optionName] = option;
		return option;
	}

	ConfigOption opIndex(string optionName)
	{
		return options.get(optionName, null);
	}

	void load()
	{
		if (!exists(filename))
			return;

		Tag root;

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

		foreach(optionPair; options.byKeyValue)
		{
			auto tags = root.tags[optionPair.key];

			if (tags.length == 1)
			{
				try
				{
					parseValue(optionPair.value, optionPair.key, tags[0].values);
					//infof("%s %s %s", optionPair.key, optionPair.value.value, optionPair.value.defaultValue);
				}
				catch(VariantException e)
				{
					warningf("Error parsing config option: %s - %s", optionPair.key, e.msg);
				}
			}
			else if (tags.length > 1)
				warningf("Multiple definitions of '%s'", optionPair.key);
			else
				warningf("Empty option '%s'", optionPair.key);
		}
	}

	void save() {}

private:

	void parseValue(ConfigOption option, string optionName, Value[] values)
	{
		if (values.length == 1)
		{
			Value value = values[0];

			if (option.value.type == typeid(bool)) {
				option.value = Variant(value.coerce!bool);
			}
			else if (option.value.type == typeid(string)) {
				option.value = Variant(value.coerce!string);
			}
			else if (option.value.convertsTo!long) {
				option.value = Variant(value.coerce!long);
			}
			else if (option.value.convertsTo!real) {
				option.value = Variant(value.coerce!double);
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
				option.value = Variant(items);
			}

			info(option.value.convertsTo!(long[]));

			if (option.value.type == typeid(long[])) {
				if (option.value.length != values.length)
					return;

				parseArray!long;
			}
			else if (option.value.type == typeid(int[])) {
				if (option.value.length != values.length)
					return;

				parseArray!int;
			}
			if (option.value.type == typeid(ulong[])) {
				if (option.value.length != values.length)
					return;

				parseArray!ulong;
			}
			else if (option.value.type == typeid(uint[])) {
				if (option.value.length != values.length)
					return;

				parseArray!uint;
			}
			else if (option.value.type == typeid(real[]) ||
				option.value.type == typeid(double[]) ||
				option.value.type == typeid(float[])) {
				if (option.value.length != values.length)
					return;

				parseArray!double;
			}
			else
			{
				warningf("Cannot parse '%s' from '%s'", optionName, values.to!string);
			}
		}
	}
}
