/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module datadriven.storage;

import datadriven.api;
import voxelman.container.buffer;
import voxelman.container.hash.map;
import voxelman.container.hash.set;
import voxelman.serialization.hashtable;

struct HashmapComponentStorage(_ComponentType)
{
	private HashMap!(EntityId, ComponentType, EntityId.max, EntityId.max-1) components;
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

	int opApply(scope int delegate(in EntityId, ref ComponentType) del) {
		return components.opApply(del);
	}

	void serialize(Buffer!ubyte* sink)
	{
		serializeMap(components, sink);
	}

	void serializePartial(Buffer!ubyte* sink, HashSet!EntityId externalEntities)
	{
		serializeMapPartial(components, sink, externalEntities);
	}

	void deserialize(ubyte[] input)
	{
		deserializeMap(components, input);
	}
}

static assert(isComponentStorage!(HashmapComponentStorage!int, int));

struct EntitySet
{
	private HashSet!EntityId entities;

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

	int opApply(scope int delegate(in EntityId) del) {
		return entities.opApply(del);
	}

	void serialize(Buffer!ubyte* sink)
	{
		serializeSet(entities, sink);
	}

	void serializePartial(Buffer!ubyte* sink, HashSet!EntityId externalEntities)
	{
		serializeSetPartial(entities, sink, externalEntities);
	}

	void deserialize(ubyte[] input)
	{
		deserializeSet(entities, input);
	}
}

static assert(isEntitySet!(EntitySet));
