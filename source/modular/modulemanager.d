module modular.modulemanager;

import std.stdio;
import std.string : format;
import modular;

/// Simple implementation of IModuleManager
// See GameModule for example usage
class ModuleManager : IModuleManager
{
	IModule[string] modules;

	void registerModule(IModule moduleInstance)
	{
		assert(moduleInstance);
		modules[moduleInstance.name] = moduleInstance;
	}

	void loadModules()
	{
		foreach(IModule m; modules)
		{
			m.load();
			writefln("Loaded module %s %s", m.name, m.semver);
		}
	}

	void initModules()
	{
		foreach(IModule m; modules)
		{
			m.init(this);
			writefln("Inited module %s %s", m.name, m.semver);
		}
	}

	IModule findModule(IModule requester, string moduleName)
	{
		if (auto mod = moduleName in modules)
			return *mod;
		else
			throw new Exception(format("Module %s requested module %s that was not registered",
				requester, moduleName));
	}
}