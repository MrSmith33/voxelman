module cons;

import pluginlib.pluginregistry;
void register(ref PluginRegistry registry)
{
	void regPlugin(string moduleName)()
	{
		mixin("import "~moduleName~".plugininfo;");
		mixin(moduleName~".plugininfo.register(registry);");
	}

	regPlugin!"voxelman.block";
	regPlugin!"voxelman.blockentity";
	regPlugin!"voxelman.chat";
	regPlugin!"voxelman.client";
	regPlugin!"voxelman.command";
	regPlugin!"voxelman.config";
	regPlugin!"voxelman.dbg";
	regPlugin!"voxelman.edit";
	regPlugin!"voxelman.entity";
	regPlugin!"voxelman.eventdispatcher";
	regPlugin!"voxelman.graphics";
	regPlugin!"voxelman.gui";
	regPlugin!"voxelman.input";
	regPlugin!"voxelman.movement";
	regPlugin!"voxelman.net";
	regPlugin!"voxelman.remotecontrol";
	regPlugin!"voxelman.server";
	regPlugin!"voxelman.session";
	regPlugin!"voxelman.world";
	regPlugin!"voxelman.worldinteraction";

	regPlugin!"railroad";

	regPlugin!"test.avatar";
	regPlugin!"test.entitytest";

	//regPlugin!"sampleplugin";
	//regPlugin!"ext.mcblocks";
	regPlugin!"exampleplugin";
}
