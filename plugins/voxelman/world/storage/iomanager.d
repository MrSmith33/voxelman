/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.iomanager;

import pluginlib;
import voxelman.config.configmanager : ConfigOption, ConfigManager;
import voxelman.world.storage.plugindata;

alias SaveHandler = void delegate(ref PluginDataSaver);
alias LoadHandler = void delegate(ref PluginDataLoader);

final class IoManager : IResourceManager
{
	package(voxelman.world) LoadHandler[] worldLoadHandlers;
	package(voxelman.world) SaveHandler[] worldSaveHandlers;

private:
	ConfigOption saveDirOpt;
	ConfigOption worldNameOpt;
	void delegate(string) onPostInit;

public:
	this(void delegate(string) onPostInit)
	{
		this.onPostInit = onPostInit;
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

	void registerWorldLoadSaveHandlers(LoadHandler loadHandler, SaveHandler saveHandler)
	{
		worldLoadHandlers ~= loadHandler;
		worldSaveHandlers ~= saveHandler;
	}
}
