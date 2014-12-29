module modular.imodulemanager;

import modular;

interface IModuleManager
{
	/// Returns reference to module instance if moduleName was registered.
	IModule findModule(IModule requester, string moduleName);
}

M getModule(M)(IModuleManager modman, IModule requester, string moduleName = M.stringof)
{
	import std.exception : enforce;
	IModule mod = modman.findModule(requester, moduleName);
	M exactModule = cast(M)mod;
	enforce(exactModule);
	return exactModule;
}