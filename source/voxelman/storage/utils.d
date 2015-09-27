/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.storage.utils;

import std.experimental.logger;
import std.math : floor;
import std.range : chain, only;
import dlib.math.vector;

import voxelman.config;
import voxelman.storage.region;

size_t manhattanDist(ivec3 position, ivec3 other)
{
	return other.x > position.x ? other.x - position.x : position.x - other.x +
			other.y > position.y ? other.y - position.y : position.y - other.y +
			other.z > position.z ? other.z - position.z : position.z - other.z;
}

double euclidDist(ivec3 position, ivec3 other)
{
	import std.math : sqrt;
	return sqrt(cast(real)(position.x - other.x)^^2 +
			(position.y - other.y)^^2 +
			(position.z - other.z)^^2);
}

size_t euclidDistSqr(ivec3 position, ivec3 other)
{
	return (position.x - other.x)^^2 + (position.y - other.y)^^2 + (position.z - other.z)^^2;
}
