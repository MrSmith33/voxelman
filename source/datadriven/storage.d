module datadriven.storage;

import datadriven.api;

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
}

static assert(isComponentStorage!(HashmapComponentStorage!int, int));
