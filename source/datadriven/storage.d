/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module datadriven.storage;

import std.range : save;
import datadriven.api;
import cbor;
import voxelman.container.buffer;
import voxelman.container.hashmap;
import voxelman.container.intkeyhashset;

struct HashmapComponentStorage(_ComponentType)
{
	private HashMap!(EntityId, ComponentType) components;
	alias ComponentType = _ComponentType;

	void set(EntityId eid, ComponentType component)
	{
		components[eid] = component;
	}

	void remove(EntityId eid)
	{
		components.remove(eid);
	}

	void removeAll()
	{
		components.clear();
	}

	size_t length() @property
	{
		return components.length;
	}

	ComponentType* get(EntityId eid)
	{
		return eid in components;
	}

	ComponentType* getOrCreate(EntityId eid, ComponentType defVal = ComponentType.init)
	{
		return components.getOrCreate(eid, defVal);
	}

	int opApply(scope int delegate(EntityId, ref ComponentType) del) {
		return components.opApply(del);
	}

	void serialize(Buffer!ubyte* sink)
	{
		if (components.empty) return;

		encodeCborMapHeader(sink, components.length);
		foreach(key, value; components) {
			encodeCbor!(Yes.Flatten)(sink, key);
			encodeCbor!(Yes.Flatten)(sink, value);
		}
	}

	void serializePartial(Buffer!ubyte* sink, IntKeyHashSet!EntityId externalEntities)
	{
		if (components.empty) return;

		encodeCborMapHeader(sink);

		if (externalEntities.length < components.length) {
			foreach(eid; externalEntities) {
				if (auto value = eid in components) {
					encodeCbor!(Yes.Flatten)(sink, eid);
					encodeCbor!(Yes.Flatten)(sink, *value);
				}
			}
		} else {
			foreach(eid, value; components) {
				if (externalEntities[eid]) {
					encodeCbor!(Yes.Flatten)(sink, eid);
					encodeCbor!(Yes.Flatten)(sink, value);
				}
			}
		}
		encodeCborBreak(sink);
	}

	void deserialize(ubyte[] input)
	{
		if (input.length == 0) return;
		CborToken token = decodeCborToken(input);
		if (token.type == CborTokenType.mapHeader) {
			size_t lengthToRead = cast(size_t)token.uinteger;
			components.reserve(lengthToRead);
			while (lengthToRead > 0) {
				auto eid = decodeCborSingle!EntityId(input);
				auto component = decodeCborSingleDup!(ComponentType, Yes.Flatten)(input);
				components[eid] = component;
				--lengthToRead;
			}
		} else if (token.type == CborTokenType.mapIndefiniteHeader) {
			while (true) {
				token = decodeCborToken(input.save);
				if (token.type == CborTokenType.breakCode) {
					break;
				} else {
					auto eid = decodeCborSingle!EntityId(input);
					auto component = decodeCborSingleDup!(ComponentType, Yes.Flatten)(input);
					components[eid] = component;
				}
			}
		}
	}
}

static assert(isComponentStorage!(HashmapComponentStorage!int, int));

struct EntitySet
{
	private IntKeyHashSet!EntityId entities;

	void set(EntityId eid)
	{
		entities.put(eid);
	}

	void remove(EntityId eid)
	{
		entities.remove(eid);
	}

	void removeAll()
	{
		entities.clear();
	}

	size_t length() @property
	{
		return entities.length;
	}

	bool get(EntityId eid)
	{
		return eid in entities;
	}

	int opApply(scope int delegate(EntityId) del) {
		return entities.opApply(del);
	}

	void serialize(Buffer!ubyte* sink)
	{
		if (entities.empty) return;

		encodeCborArrayHeader(sink, entities.length);
		foreach(eid; entities) {
			encodeCbor(sink, eid);
		}
	}

	void serializePartial(Buffer!ubyte* sink, IntKeyHashSet!EntityId externalEntities)
	{
		if (entities.empty) return;
		encodeCborMapHeader(sink);

		if (externalEntities.length < entities.length) {
			foreach(eid; externalEntities)
				if (entities[eid]) encodeCbor(sink, eid);
		} else {
			foreach(eid; entities)
				if (externalEntities[eid]) encodeCbor(sink, eid);
		}
		encodeCborBreak(sink);
	}

	void deserialize(ubyte[] input)
	{
		if (input.length == 0) return;
		CborToken token = decodeCborToken(input);
		if (token.type == CborTokenType.arrayHeader) {
			size_t lengthToRead = cast(size_t)token.uinteger;
			entities.reserve(lengthToRead);
			while (lengthToRead > 0) {
				entities.put(decodeCborSingle!EntityId(input));
				--lengthToRead;
			}
		} else if (token.type == CborTokenType.arrayIndefiniteHeader) {
			while (true) {
				token = decodeCborToken(input.save);
				if (token.type == CborTokenType.breakCode)
					break;
				else
					entities.put(decodeCborSingle!EntityId(input));
			}
		}
	}
}

static assert(isEntitySet!(EntitySet));
