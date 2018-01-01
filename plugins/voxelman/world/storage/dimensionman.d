/**
Copyright: Copyright (c) 2016-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.dimensionman;

import std.typecons : Nullable;
import voxelman.log;
import voxelman.math;
import voxelman.core.config;
import voxelman.world.storage;
import voxelman.world.gen.generatorman;

struct DimensionInfo
{
	string name;
	ClientDimPos spawnPos;

	Box borders = Box(ivec3(-int.max/2, -int.max/2, -int.max/2), ivec3(int.max, int.max, int.max));
}

struct DimensionManager {
	DimensionInfo[DimensionId] dimensions;
	GeneratorManager generatorMan;
	auto dbKey = IoKey("voxelman.world.storage.dimensionman");

	void load(ref PluginDataLoader loader) {
		generatorMan.load(loader);
		loader.readEntryDecoded(dbKey, dimensions);
	}

	void save(ref PluginDataSaver saver) {
		generatorMan.save(saver);
		saver.writeEntryEncoded(dbKey, dimensions);
	}

	bool contains(DimensionId dim) {
		return !!(dim in dimensions);
	}

	/// returns internal pointer to hashmap. add/remove can invalidate pointers.
	DimensionInfo* opIndex(DimensionId dim) {
		return dim in dimensions;
	}

	DimensionInfo* getOrCreate(DimensionId dim) {
		auto dimension = dim in dimensions;
		if (dimension)
			return dimension;

		dimensions[dim] = DimensionInfo();
		return dim in dimensions;
	}

	void opIndexAssign(DimensionInfo value, DimensionId key) {
		assert(key !in dimensions);
		dimensions[key] = value;
	}

	void remove(DimensionId dim) {
		dimensions.remove(dim);
	}

	Box dimensionBorders(DimensionId dim) {
		auto dimension = dim in dimensions;
		if (dimension)
			return dimension.borders;
		return DimensionInfo.init.borders;
	}
}
