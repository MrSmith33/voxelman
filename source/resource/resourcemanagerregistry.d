/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module resource.resourcemanagerregistry;

import std.experimental.logger;
import std.string : format;
import resource;

/// Simple implementation of IResourceManagerManager
class ResourceManagerRegistry : IResourceManagerRegistry
{
	IResourceManager[string] resourceManagers;

	void registerResourceManager(IResourceManager resourceManagerInstance)
	{
		assert(resourceManagerInstance);
		assert(resourceManagerInstance.name !in resourceManagers,
			format("Duplicate resource manager registered: name=\"%s\" type=\"%s\"",
				resourceManagerInstance.name, resourceManagerInstance));
		resourceManagers[resourceManagerInstance.name] = resourceManagerInstance;
	}

	void initResourceManagers()
	{
		foreach(IResourceManager p; resourceManagers)
		{
			p.preInit();
		}
		foreach(IResourceManager p; resourceManagers)
		{
			p.init(this);
		}
	}

	void loadResources()
	{
		foreach(IResourceManager p; resourceManagers)
		{
			p.loadResources();
		}
	}

	void postInitResourceManagers()
	{
		foreach(IResourceManager p; resourceManagers)
		{
			p.postInit();
		}
	}

	IResourceManager findResourceManager(string resourceManagerName)
	{
		if (auto resman = resourceManagerName in resourceManagers)
			return *resman;
		else
			throw new Exception(format("requested resourceManager '%s' that was not registered",
				resourceManagerName));
	}
}
