/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.utils.mapping;

struct Mapping(InfoType, bool withTypeMap = false)
{
	static assert(__traits(compiles, {InfoType info; info.id=1; info.name="str";}),
		"InfoType is required to have size_t id; and string name; properties");

	InfoType[] infoArray;
	size_t[string] nameToIndexMap;

	static if (withTypeMap)
		size_t[TypeInfo] typeToIndexMap;

	size_t length() @property
	{
		return infoArray.length;
	}

	ref InfoType opIndex(size_t id)
	{
		return infoArray[id];
	}

	static if (withTypeMap)
	{
		size_t put(T)(InfoType info)
		{
			size_t newId = putImpl(info);
			assert(typeid(T) !in typeToIndexMap, "Type "~T.stringof~" was already registered");
			typeToIndexMap[typeid(T)] = newId;
			return newId;
		}

		bool contains(T)()
		{
			return typeid(T) in typeToIndexMap;
		}

		size_t id(T)()
		{
			return typeToIndexMap.get(typeid(T), size_t.max);
		}
	} else {
		size_t put(InfoType info)
		{
			return putImpl(info);
		}
	}

	private size_t putImpl(InfoType info)
	{
		size_t newId = infoArray.length;
		nameToIndexMap[info.name] = newId;
		info.id = newId;
		infoArray ~= info;
		return newId;
	}

	auto nameRange() @property
	{
		import std.algorithm : map;
		return infoArray.map!(a => a.name);
	}

	size_t id(string name)
	{
		return nameToIndexMap.get(name, size_t.max);
	}

	string name(size_t id)
	{
		import std.string : format;
		if (id >= infoArray.length) return format("|Unknown %s %s|", InfoType.stringof, id);
		return infoArray[id].name;
	}

	void setMapping(R)(R names)
	{
		import std.range : isInputRange, hasLength;
		static assert(isInputRange!R, "names should be InputRange of strings");

		InfoType[] newArray;
		static if (hasLength!R)
		{
			if (names.length == 0)
			{
				return;
			}
			newArray.reserve(names.length);
		}

		foreach(i, name; names)
		{
			size_t index = nameToIndexMap.get(name, size_t.max);
			size_t newId = newArray.length;

			if (index == size_t.max)
			{
				InfoType info;
				info.name = name;
				newArray ~= info;
			}
			else
			{
				newArray ~= infoArray[index];
				infoArray[index].id = size_t.max; // Mark as removed
			}
			newArray[$-1].id = newId;
		}
		infoArray = newArray;

		size_t[string] newMap;
		foreach(ref info; infoArray)
		{
			newMap[info.name] = info.id;
		}
		nameToIndexMap = newMap;
	}
}

//static assert(__traits(compiles, {struct   ValidInfo {size_t id; string name;} Mapping!ValidInfo m;}));
//static assert(!is(typeof({struct InvalidInfo {} Mapping!InvalidInfo invmapping;})));
//static assert(!is(typeof({struct InvalidInfo {size_t id;} Mapping!InvalidInfo invmapping;})));
//static assert(!is(typeof({struct InvalidInfo {string name;} Mapping!InvalidInfo invmapping;})));
unittest
{
	//import std.stdio;
	struct Info
	{
		string name;
		size_t id;
	}

	Mapping!(Info) mapping;
	mapping.setMapping(["first", "second"]);
	mapping.put(Info("third"));
	assert(mapping[0].name == "first");
	assert(mapping[1].name == "second");
	assert(mapping[2].name == "third");

	Mapping!(Info, true) mappingTyped;
	mappingTyped.setMapping(["first", "second"]);
	mappingTyped.put!int(Info("third"));
	assert(mappingTyped[0].name == "first");
	assert(mappingTyped[1].name == "second");
	assert(mappingTyped[2].name == "third");
	assert(mappingTyped.id!int == 2);
	assert(mappingTyped.id!bool == size_t.max);
}
