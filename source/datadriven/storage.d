module datadriven.storage;

import datadriven.api;
import cbor;

struct HashmapComponentStorage(ComponentType)
{
	private ComponentType[EntityId] components;

	void add(EntityId eid, ComponentType component)
	{
		//assert(eid !in components);
		components[eid] = component;
	}

	void remove(EntityId eid)
	{
		components.remove(eid);
	}

	void removeAll()
	{
		components = null;
	}

	size_t length() @property
	{
		return components.length;
	}

	ComponentType* get(EntityId eid)
	{
		return eid in components;
	}

	auto byKeyValue() @property
	{
		return components.byKeyValue;
	}

	void serialize(Sink)(Sink sink)
	{
		size_t size = encodeCborMapHeader(sink, components.length);
		foreach(keyValue; components.byKeyValue) {
			encodeCbor(sink, keyValue.key);
			encodeCbor(sink, keyValue.value);
		}
	}

	void deserialize(ubyte[] input)
	{
		components = null;//.clear(); //introduced in 2.071
		decodeCbor(input, components);
	}
}

static assert(isComponentStorage!(HashmapComponentStorage!int, int));
