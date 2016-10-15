/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.storage.dimensionman;

import voxelman.log;
import voxelman.geometry.box;
import std.typecons : Nullable;
import voxelman.math;
import voxelman.core.config;
import voxelman.world.storage;

struct DimensionInfo
{
	DimensionId id;
	string name;
	vec3 spawnPos;
	vec2 spawnRotation;

	Box borders = Box(ivec3(-int.max, -int.max, -int.max), ivec3(int.max, int.max, int.max));
}

struct DimensionManager {
	DimensionInfo[DimensionId] dimensions;
	auto dbKey = IoKey("voxelman.world.storage.dimensionman");

	void load(ref PluginDataLoader loader) {
		loader.readEntryDecoded(dbKey, dimensions);
	}

	void save(ref PluginDataSaver saver) {
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

		dimensions[dim] = DimensionInfo(dim);
		return dim in dimensions;
	}

	void opIndexAssign(DimensionInfo value, DimensionId key) {
		assert(key !in dimensions);
		dimensions[key] = value;
	}

	void remove(DimensionId dim) {
		dimensions.remove(dim);
	}
}
