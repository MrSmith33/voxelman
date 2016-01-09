module voxelman.block.plugin;

import pluginlib;
import voxelman.core.config : BlockId;

shared static this()
{
	pluginRegistry.regClientPlugin(new BlockPlugin);
	pluginRegistry.regServerPlugin(new BlockPlugin);
}

final class BlockPlugin : IPlugin
{
	// IPlugin stuff
	mixin IdAndSemverFrom!(voxelman.block.plugininfo);

	override void registerResourceManagers(void delegate(IResourceManager) registerHandler)
	{
		registerHandler(new BlockManager);
	}
	override void registerResources(IResourceManagerRegistry resmanRegistry) {}
	override void preInit() {}
	override void init(IPluginManager pluginman) {}
	override void postInit() {}
}

final class BlockManager : IResourceManager
{
	override string id() @property { return "voxelman.blockmanager"; }
	override void preInit() {}
	override void init(IResourceManagerRegistry resmanRegistry) {}
	override void loadResources() {}
	override void postInit() {}

	BlockId regBlock()
	{
		return 0;
	}
}
