/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.iomanager;

import voxelman.log;
import std.experimental.allocator.mallocator;
import std.bitmanip;

import cbor;
import pluginlib;
import voxelman.core.config;
import voxelman.config.configmanager : ConfigOption, ConfigManager;
import voxelman.world.worlddb;
import voxelman.utils.mapping;
import voxelman.serialization;


alias SaveHandler = void delegate(ref PluginDataSaver);
alias LoadHandler = void delegate(ref PluginDataLoader);

final class IoManager : IResourceManager
{
	package(voxelman.world) LoadHandler[] worldLoadHandlers;
	package(voxelman.world) SaveHandler[] worldSaveHandlers;
	StringMap stringMap;

private:
	ConfigOption saveDirOpt;
	ConfigOption worldNameOpt;

	void delegate(string) onPostInit;

	auto dbKey = IoKey(null);
	void loadStringKeys(ref PluginDataLoader loader) {
		stringMap.load(loader.readEntryDecoded!(string[])(dbKey));
		if (stringMap.strings.length == 0) {
			stringMap.put(null); // reserve 0 index for string map
		}
	}

	void saveStringKeys(ref PluginDataSaver saver) {
		saver.writeEntryEncoded(dbKey, stringMap.strings);
	}

public:
	this(void delegate(string) onPostInit)
	{
		this.onPostInit = onPostInit;
		stringMap.put(null); // reserve 0 index for string map
		worldLoadHandlers ~= &loadStringKeys;
		worldSaveHandlers ~= &saveStringKeys;
	}

	override string id() @property { return "voxelman.world.iomanager"; }

	override void init(IResourceManagerRegistry resmanRegistry) {
		ConfigManager config = resmanRegistry.getResourceManager!ConfigManager;
		saveDirOpt = config.registerOption!string("save_dir", "../../saves");
		worldNameOpt = config.registerOption!string("world_name", "world");
	}
	override void postInit() {
		import std.path : buildPath;
		import std.file : mkdirRecurse;
		auto saveFilename = buildPath(saveDirOpt.get!string, worldNameOpt.get!string~".db");
		mkdirRecurse(saveDirOpt.get!string);
		onPostInit(saveFilename);
	}

	StringMap* getStringMap() {
		return &stringMap;
	}

	void registerWorldLoadSaveHandlers(LoadHandler loadHandler, SaveHandler saveHandler)
	{
		worldLoadHandlers ~= loadHandler;
		worldSaveHandlers ~= saveHandler;
	}
}
