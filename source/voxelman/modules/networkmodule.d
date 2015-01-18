module modular.modules.networkmodule;

import modular;

import modular.modules.mainloopmodule;

class NetworkModule : IModule, IUpdatableModule
{
	override string name() @property { return "NetworkModule"; }
	override string semver() @property { return "1.0.0"; }
	override void load()
	{
		// load enet
		registerPacket!PacketMapPacket();
	}

	override void init(IModuleManager moduleman)
	{
		mainmod = moduleman.getModule!MainLoopModule(this);
		mainmod.registerUpdatableModule(this);
	}

	override void update(double delta)
	{
		// enet_host_service
	}

	//
	void registerPacket(P)()
	{
		packets ~= typeid(P);
	}

private:
	MainLoopModule mainmod;

	TypeInfo[] packets;
}

struct PacketMapPacket
{
	string[] packets;
}