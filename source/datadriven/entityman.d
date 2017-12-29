/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module datadriven.entityman;

import cbor;
import voxelman.log;
import datadriven.api;
import datadriven.storage;
import datadriven.query;
import voxelman.container.buffer;
import voxelman.container.hash.set;
import voxelman.serialization;

private struct ComponentInfo
{
	IoKey ioKey;
	bool serializeToDb;
	bool serializeToNet;
	void delegate(EntityId) remove;
	void delegate() removeAll;
	void delegate(Buffer!ubyte*) serialize;
	void delegate(Buffer!ubyte*, HashSet!EntityId) serializePartial;
	void delegate(ubyte[]) deserialize;
	void* storage;

	bool isSerialized(IoStorageType storageType) {
		final switch(storageType) {
			case IoStorageType.database: return serializeToDb;
			case IoStorageType.network: return serializeToNet;
		}
	}

	ComponentStorage!C* getTypedStorage(C)() {
		return cast(ComponentStorage!C*)storage;
	}
}

enum bool isTagComponent(C) = C.tupleof.length == 0;

private struct _Totally_empty_struct {}
static assert(isTagComponent!_Totally_empty_struct);

template ComponentStorage(C)
{
	static if(isTagComponent!C)
		alias ComponentStorage = EntitySet;
	else
		alias ComponentStorage = HashmapComponentStorage!C;
}

struct EntityIdManager
{
	private EntityId lastEntityId; // 0 is reserved
	IoKey ioKey = IoKey("voxelman.entity.lastEntityId");

	EntityId nextEntityId()
	{
		return ++lastEntityId;
	}

	void load(ref PluginDataLoader loader)
	{
		loader.readEntryDecoded(ioKey, lastEntityId);
	}

	void save(ref PluginDataSaver saver)
	{
		saver.writeEntryEncoded(ioKey, lastEntityId);
	}
}

/// Convenience type for centralized storage and management of entity components.
struct EntityManager
{
	private ComponentInfo*[TypeInfo] componentInfoMap;
	private ComponentInfo*[] componentInfoArray;
	EntityIdManager* eidMan;

	/// Before using component type in every other method, register it here.
	/// name is used for (de)serialization.
	void registerComponent(C)()
	{
		assert(typeid(C) !in componentInfoMap);
		auto storage = new ComponentStorage!C;
		auto info =	new ComponentInfo(
			IoKey(componentUda!C.key),
			cast(bool)(componentUda!C.replication & Replication.toDb),
			cast(bool)(componentUda!C.replication & Replication.toClient),
			&storage.remove,
			&storage.removeAll,
			&storage.serialize,
			&storage.serializePartial,
			&storage.deserialize,
			storage);
		componentInfoMap[typeid(C)] = info;
		componentInfoArray ~= info;

		//tracef("Register component %s", *info);
	}

	auto getIoKeys() {
		static struct IoKeyRange
		{
			ComponentInfo*[] array;
			int opApply(scope int delegate(ref IoKey) del) {
				foreach(info; array)
				{
					if (auto ret = del(info.ioKey))
						return ret;
				}
				return 0;
			}
		}

		return IoKeyRange(componentInfoArray);
	}

	/// Returns pointer to the storage of components C.
	/// Storage type depends on component type (tag or not).
	auto getComponentStorage(C)()
	{
		ComponentInfo* untyped = componentInfoMap[typeid(C)];
		return untyped.getTypedStorage!C();
	}

	/// Add or set list of components for entity eid.
	void set(Components...)(EntityId eid, Components components)
	{
		foreach(i, C; Components)
		{
			static if(isTagComponent!C)
				getComponentStorage!C().set(eid);
			else
				getComponentStorage!C().set(eid, components[i]);
		}
	}

	/// Returns pointer to the component of type C.
	/// Returns null if entity has no such component.
	/// Works only with non-tag components.
	C* get(C)(EntityId eid)
	{
		static assert (!isTagComponent!C, "Cannot use get for tag component, use has method");
		return getComponentStorage!C().get(eid);
	}

	/// Returns pointer to the component of type C.
	/// Creates component first if entity had no such component.
	/// Works only with non-tag components.
	C* getOrCreate(C)(EntityId eid, C defVal = C.init)
	{
		static assert (!isTagComponent!C, "Cannot use getOrCreate for tag component");
		return getComponentStorage!C().getOrCreate(eid, defVal);
	}

	/// Used to check for presence of given component or tag.
	bool has(C)(EntityId eid)
	{
		return cast(bool)getComponentStorage!C().get(eid);
	}

	/// Removes one component for given eid.
	void remove(C)(EntityId eid)
	{
		getComponentStorage!C().remove(eid);
	}

	/// Removes all components for given eid.
	void remove(EntityId eid)
	{
		foreach(info; componentInfoArray)
		{
			info.remove(eid);
		}
	}

	/// Removes all components of all types.
	void removeAll()
	{
		foreach(info; componentInfoArray)
		{
			info.removeAll();
		}
	}

	/// Returns query object for given set of component types for iteration with foreach.
	/// Will pass EntityId, followed by pointers to components. Flag components are omitted.
	/// Example:
	/// ---
	/// auto query = eman.query!(Position, Velocity, IsMovable);
	///	foreach(EntityId id, Position* position, Velocity* velocity; query)
	/// {
	/// 	position.vector += velocity.vector;
	/// }
	/// ---
	auto query(Components...)()
	{
		// generate variables for typed storages
		mixin(genTempComponentStorages!Components);
		// populate variables
		foreach(i, C; Components)
		{
			mixin(genComponentStorageName!(ComponentStorage!C, i)) =
				getComponentStorage!C();
		}
		// construct query with storages
		return mixin(genQueryCall!Components);
	}

	/// Serializes all component storages with given saver.
	void save(Saver)(ref Saver saver)
	{
		foreach(info; componentInfoArray) {
			if(!info.isSerialized(saver.storageType)) continue;
			info.serialize(saver.beginWrite());
			saver.endWrite(info.ioKey);
		}
	}

	void savePartial(Saver, E)(ref Saver saver, E entities)
	{
		foreach(info; componentInfoArray) {
			if(!info.isSerialized(saver.storageType)) continue;
			info.serializePartial(saver.beginWrite(), entities);
			saver.endWrite(info.ioKey);
		}
	}

	/// Deserializes all component storages from given loader.
	void load(Loader)(ref Loader loader, bool removeBeforeRead = true)
	{
		foreach(info; componentInfoArray) {
			if(!info.isSerialized(loader.storageType)) continue;
			auto data = loader.readEntryRaw(info.ioKey);
			if (removeBeforeRead)
				info.removeAll();
			info.deserialize(data);
		}
	}

	void removeSerializedComponents(IoStorageType storageType)
	{
		foreach(info; componentInfoArray) {
			if(info.isSerialized(storageType))
				info.removeAll();
		}
	}
}

private string genTempComponentStorages(Components...)()
{
	import std.conv : to;
	string result;

	foreach(i, C; Components)
	{
		result ~= "ComponentStorage!(Components[" ~ i.to!string ~ "])* " ~
			genComponentStorageName!(ComponentStorage!C, i) ~ ";\n";
	}

	return result;
}

private string genQueryCall(Components...)()
{
	string result = "componentQuery(";

	foreach(i, C; Components)
	{
		result ~= "*" ~ genComponentStorageName!(ComponentStorage!C, i) ~ ",";
	}
	result ~= ")";

	return result;
}
