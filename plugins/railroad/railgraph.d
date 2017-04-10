/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module railroad.railgraph;

import voxelman.container.hash.map;
import voxelman.math;

import voxelman.world.storage;
import railroad.utils;


struct RailGraph
{
	HashMap!(RailPos, RailData) rails;

	auto dbKey = IoKey("railroad.rail_graph");

	void read(ref PluginDataLoader loader)
	{
		ubyte[] data = loader.readEntryRaw(dbKey);

	}

	void write(ref PluginDataSaver saver)
	{

	}

	void onRailAdd(RailPos pos, RailData railData)
	{
		auto data = rails.getOrCreate(pos, RailData());
		data.addRail(railData);
	}

	void onRailRemove(RailPos pos, RailData railData)
	{
		auto data = pos in rails;
		if (data) {
			(*data).removeRail(railData);
			if (data.empty) {
				rails.removeByPtr(data);
			}
		}
	}
}
