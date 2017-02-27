/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module railroad.railgraph;

import voxelman.container.hashmap;
import voxelman.math;

import voxelman.world.storage;
import railroad.utils;

struct EdgesAtRailPos
{
	RailGraphEdgeId[2] edges;
}

///
struct RailGraphEdge
{
	RailPos from;
	RailPos to;
	RailData data;
}

// 0 is invalid id
alias RailGraphEdgeId = uint;
enum NULL_RAIL_POS = RailPos(svec4(short.max,short.max,short.max,short.max));

struct RailGraph
{
	HashMap!(ulong, EdgesAtRailPos) railToEdges;
	HashMap!(RailGraphEdgeId, RailGraphEdge) edges;

	auto dbKey = IoKey("railroad.rail_graph");

	void read(ref PluginDataLoader loader)
	{

	}

	void write(ref PluginDataSaver saver)
	{

	}

	void onRailAdd(RailPos pos, RailData railData)
	{

	}

	void onRailRemove(RailPos pos, RailData railData)
	{

	}
}
