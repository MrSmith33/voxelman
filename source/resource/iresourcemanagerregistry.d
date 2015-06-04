/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module resource.iresourcemanagerregistry;

import resource;

interface IResourceManagerRegistry
{
	/// Returns reference to ResourceManager instance if resmanName was registered.
	IResourceManager findResourceManager(string resmanName);
}

RM getResourceManager(RM)(IResourceManagerRegistry resmanRegistry, string resmanName = RM.stringof)
{
	import std.exception : enforce;
	IResourceManager resman = resmanRegistry.findResourceManager(resmanName);
	RM exactResman = cast(RM)resman;
	enforce(exactResman);
	return exactResman;
}
