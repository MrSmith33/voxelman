/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module railroad.railgraph;

import voxelman.container.hash.map;
import voxelman.math;
import voxelman.log;
import voxelman.serialization.hashtable;

import voxelman.world.storage;
import railroad.utils;


struct RailGraph
{
	HashMap!(RailPos, RailData) rails;

	auto dbKey = IoKey("railroad.rail_graph");

	void read(ref PluginDataLoader loader)
	{
		ubyte[] data = loader.readEntryRaw(dbKey);
		deserializeMap(rails, data);
	}

	void write(ref PluginDataSaver saver)
	{
		auto sink = saver.beginWrite();
		serializeMap(rails, sink);
		saver.endWrite(dbKey);
	}

	void onRailEdit(RailPos pos, RailData railData, RailEditOp editOp)
	{
		final switch(editOp)
		{
			case RailEditOp.add: onRailAdd(pos, railData); break;
			case RailEditOp.remove: onRailRemove(pos, railData); break;
		}
	}

	void onRailAdd(RailPos pos, RailData railData)
	{
		auto data = rails.getOrCreate(pos, RailData());
		data.addRail(railData);
	}

	void onRailRemove(RailPos pos, RailData railData)
	{
		if (auto data = pos in rails) {
			(*data).removeRail(railData);
			if ((*data).empty) {
				rails.removeByPtr(data);
			}
		}
	}
}
