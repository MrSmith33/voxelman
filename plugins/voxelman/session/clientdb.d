/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.session.clientdb;

import netlib : SessionId;
import datadriven;
import std.typecons : Nullable;
import voxelman.world.storage;

struct ClientDb
{
	private auto ioKey = IoKey("voxelman.session.clientdb.nameToKeyMap");

	private EntityId[string] nameToKeyMap;
	EntityManager* eman;

	EntityId getOrCreate(string name, out bool createdNew) {
		auto idPtr = name in nameToKeyMap;
		createdNew = false;
		if (idPtr)
			return *idPtr;
		else
		{
			createdNew = true;
			auto newId = eman.eidMan.nextEntityId;
			nameToKeyMap[name] = newId;
			return newId;
		}
	}

	// returns 0 if doesn't exist
	EntityId getIdForName(string name) {
		return nameToKeyMap.get(name, 0);
	}

	// hasConflict returns true if there is conflict
	string resolveNameConflict(string conflictingName,
		bool delegate(string) hasConflict)
	{
		import std.regex : matchFirst, regex;
		import std.conv : to;
		import voxelman.utils.textformatter;

		auto re = regex(`(.*)(\d+)$`, "m");
		auto captures = matchFirst(conflictingName, re);

		string firstNamePart = conflictingName;
		int counter = 1;
		if (!captures.empty)
		{
			firstNamePart = captures[1];
			counter = to!int(captures[2]);
		}

		const(char)[] newName;

		do
		{
			newName = makeFormattedText("%s%s", firstNamePart, counter);
			++counter;
		}
		while(hasConflict(cast(string)newName));

		return newName.idup;
	}

	// forward methods of eman
	bool has(C)(EntityId eid) { return eman.has!C(eid); }
	void set(C...)(C c) { eman.set(c); }
	C* get(C)(EntityId eid) { return eman.get!C(eid); }
	C* getOrCreate(C)(EntityId eid) { return eman.getOrCreate!C(eid); }
	void remove(C)(EntityId eid) { eman.remove!C(eid); }

	void load(ref PluginDataLoader loader)
	{
		loader.readEntryDecoded(ioKey, nameToKeyMap);
	}

	void save(ref PluginDataSaver saver)
	{
		saver.writeEntryEncoded(ioKey, nameToKeyMap);
	}
}
