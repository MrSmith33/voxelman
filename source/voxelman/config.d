/**
Copyright: Copyright (c) 2014-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.config;

import std.experimental.logger;
import std.file : read, exists;
public import std.variant;
import std.traits : isArray;

import dlib.math.vector : vec3, ivec3, ivec4, uvec2;
import sdlang;

import plugin;


alias BlockType = ubyte;
alias TimestampType = ulong;

enum CHUNK_SIZE = 32;
enum CHUNK_SIZE_BITS = CHUNK_SIZE - 1;
enum CHUNK_SIZE_SQR = CHUNK_SIZE * CHUNK_SIZE;
enum CHUNK_SIZE_CUBE = CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE;

// directories
enum string SAVE_DIR = "../saves";
enum string WORLD_NAME = "world";
enum string WORLD_DIR = SAVE_DIR ~ "/" ~ WORLD_NAME;
enum string WORLD_FILE_NAME = "worldinfo.cbor";

enum string CLIENT_CONFIG_FILE_NAME = "../config/client.sdl";

enum NUM_WORKERS = 4;
enum DEFAULT_VIEW_RADIUS = 5;
enum MIN_VIEW_RADIUS = 1;
enum MAX_VIEW_RADIUS = 12;
enum WORLD_SIZE = 12; // chunks
enum BOUND_WORLD = false;

enum START_POS = vec3(0, 100, 0);

enum ENABLE_RLE_PACKET_COMPRESSION = true;

enum SERVER_UPDATES_PER_SECOND = 240;
enum size_t SERVER_FRAME_TIME_USECS = 1_000_000 / SERVER_UPDATES_PER_SECOND;
enum SERVER_PORT = 1234;

final class ConfigOption
{
	this(Variant value, Variant defaultValue)
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

	Variant value;
	Variant defaultValue;
}

final class Config
{
private:
	ConfigOption[string] options;
	string filename;

public:

	this(string filename)
	{
		this.filename = filename;
	}

	ConfigOption registerOption(T)(string optionName, T defaultValue)
	{
		auto option = new ConfigOption(Variant(defaultValue), Variant(defaultValue));
		options[optionName] = option;
		return option;
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
					infof("%s %s %s", optionPair.key, optionPair.value.value, optionPair.value.defaultValue);
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
				warningf("Cannot parse '%s' from '%s'", optionName, value);
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
				warningf("Cannot parse '%s' from '%s'", optionName, values);
			}
		}
	}
}
