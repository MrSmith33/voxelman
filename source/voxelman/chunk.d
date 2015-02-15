/**
Copyright: Copyright (c) 2013-2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.chunk;

import std.string : format;

import dlib.math.vector;

import voxelman.config;
import voxelman.block;
import voxelman.chunkmesh;
import voxelman.region;


size_t manhattanDist(ivec3 coord, ivec3 other)
{
	return other.x > coord.x ? other.x - coord.x : coord.x - other.x +
			other.y > coord.y ? other.y - coord.y : coord.y - other.y +
			other.z > coord.z ? other.z - coord.z : coord.z - other.z;
}

double euclidDist(ivec3 coord, ivec3 other)
{
	import std.math : sqrt;
	return sqrt(cast(real)(other.x > coord.x ? other.x - coord.x : coord.x - other.x)^^2 +
			(other.y > coord.y ? other.y - coord.y : coord.y - other.y)^^2 +
			(other.z > coord.z ? other.z - coord.z : coord.z - other.z)^^2);
}

size_t euclidDistSqr(ivec3 coord, ivec3 other)
{
	return (other.x > coord.x ? other.x - coord.x : coord.x - other.x)^^2 +
		(other.y > coord.y ? other.y - coord.y : coord.y - other.y)^^2 +
		(other.z > coord.z ? other.z - coord.z : coord.z - other.z)^^2;
}

ivec3 calcRegionPos(ivec3 chunkWorldPos)
{
	import std.math : floor;
	return ivec3(
		cast(int)floor(chunkWorldPos.x / cast(float)REGION_SIZE),
		cast(int)floor(chunkWorldPos.y / cast(float)REGION_SIZE),
		cast(int)floor(chunkWorldPos.z / cast(float)REGION_SIZE));
}

ivec3 calcRegionLocalPos(ivec3 chunkWorldPos)
{
	chunkWorldPos.x %= REGION_SIZE;
	chunkWorldPos.y %= REGION_SIZE;
	chunkWorldPos.z %= REGION_SIZE;
	if (chunkWorldPos.x < 0) chunkWorldPos.x += REGION_SIZE;
	if (chunkWorldPos.y < 0) chunkWorldPos.y += REGION_SIZE;
	if (chunkWorldPos.z < 0) chunkWorldPos.z += REGION_SIZE;
	return chunkWorldPos;
}

ChunkRange calcChunkRange(ivec3 coord, size_t viewRadius)
{
	auto size = viewRadius*2 + 1;
	return ChunkRange(cast(ivec3)(coord - viewRadius),
		ivec3(size, size, size));
}

ivec3 cameraToChunkPos(vec3 cameraPos)
{
	import std.conv : to;
	import std.math : isNaN;
	import voxelman.utils.math : nansToZero;

	nansToZero(cameraPos);
	return ivec3(
		cast(int)cameraPos.x / CHUNK_SIZE,
		cast(int)cameraPos.y / CHUNK_SIZE,
		cast(int)cameraPos.z / CHUNK_SIZE,);
}

// 3d slice of chunks
struct ChunkRange
{
	ivec3 coord;
	ivec3 size;

	int volume()
	{
		return size.x * size.y * size.z;
	}

	bool empty() @property
	{
		return size.x == 0 && size.y == 0 && size.z == 0;
	}

	bool contains(ivec3 otherCoord)
	{
		if (otherCoord.x < coord.x || otherCoord.x >= coord.x + size.x) return false;
		if (otherCoord.y < coord.y || otherCoord.y >= coord.y + size.y) return false;
		if (otherCoord.z < coord.z || otherCoord.z >= coord.z + size.z) return false;
		return true;
	}

	bool opEquals()(auto ref const ChunkRange other) const
	{
		return coord == other.coord && size == other.size;
	}

	import std.algorithm : cartesianProduct, map, joiner, equal, canFind;
	import std.range : iota, walkLength;
	import std.array : array;

	// generates all chunk coordinates that are contained inside chunk range.
	auto chunkCoords() @property
	{
		return cartesianProduct(
			iota(coord.x, coord.x + size.x),
			iota(coord.y, coord.y + size.y),
			iota(coord.z, coord.z + size.z))
			.map!((a)=>ivec3(a[0], a[1], a[2]));
	}

	unittest
	{
		assert(ChunkRange(ivec3(0,0,0), ivec3(3,3,3)).chunkCoords.walkLength == 27);
	}

	auto chunksNotIn(ChunkRange other)
	{
		import std.algorithm : filter;
		
		auto intersection = rangeIntersection(this, other);
		ChunkRange[] ranges;

		if (intersection.size == ivec3(0,0,0)) 
			ranges = [this];
		else
			ranges = octoSlice(intersection)[]
				.filter!((a) => a != intersection)
				.array;

		return ranges
			.map!((a) => a.chunkCoords)
			.joiner;
	}

	unittest
	{
		ChunkRange cr = {{0,0,0}, {2,2,2}};
		ChunkRange other1 = {{1,1,1}, {2,2,2}}; // opposite intersection {1,1,1}
		ChunkRange other2 = {{2,2,2}, {2,2,2}}; // no intersection
		ChunkRange other3 = {{0,0,1}, {2,2,2}}; // half intersection
		ChunkRange other4 = {{0,0,-1}, {2,2,2}}; // half intersection

		ChunkRange half1 = {{0,0,0}, {2,2,1}};
		ChunkRange half2 = {{0,0,1}, {2,2,1}};

		assert( !cr.chunksNotIn(other1).canFind(ivec3(1,1,1)) );
		assert( equal(cr.chunksNotIn(other2), cr.chunkCoords) );
		assert( equal(cr.chunksNotIn(other3), half1.chunkCoords) );
		assert( equal(cr.chunksNotIn(other4), half2.chunkCoords) );
	}

	/// Slice range in 8 pieces as octree by corner piece.
	/// Return all 8 pieces.
	/// corner piece must be in the corner of this range.
	ChunkRange[8] octoSlice(ChunkRange corner)
	{
		// opposite corner coordinates.
		int cx, cy, cz;

		if (corner.coord.x == coord.x) // x0
			cx = (corner.coord.x + corner.size.x);
		else // x1
			cx = corner.coord.x;

		if (corner.coord.y == coord.y) // y0
			cy = (corner.coord.y + corner.size.y);
		else // y1
			cy = corner.coord.y;

		if (corner.coord.z == coord.z) // z0
			cz = (corner.coord.z + corner.size.z);
		else // z1
			cz = corner.coord.z;


		// origin coordinates
		int ox = coord.x, oy = coord.y, oz = coord.z;
		// opposite corner size.
		int csizex = size.x-(cx-ox), csizey = size.y-(cy-oy), csizez = size.z-(cz-oz);
		// origin size
		int osizex = size.x-csizex, osizey = size.y-csizey, osizez = size.z-csizez;
		//writefln("cx %s cy %s cz %s", cx, cy, cz);
		//writefln("csizex %s csizey %s csizez %s", csizex, csizey, csizez);
		//writefln("ox %s oy %s oz %s", ox, oy, oz);
		//writefln("osizex %s osizey %s osizez %s", osizex, osizey, osizez);
		//writefln("sizex %s sizey %s sizez %s", size.x, size.y, size.z);
		//writefln("Corner %s", corner);

		ChunkRange rx0y0z0 = {ivec3(ox,oy,oz), ivec3(osizex, osizey, osizez)};
		ChunkRange rx0y0z1 = {ivec3(ox,oy,cz), ivec3(osizex, osizey, csizez)};
		ChunkRange rx0y1z0 = {ivec3(ox,cy,oz), ivec3(osizex, csizey, osizez)};
		ChunkRange rx0y1z1 = {ivec3(ox,cy,cz), ivec3(osizex, csizey, csizez)};

		ChunkRange rx1y0z0 = {ivec3(cx,oy,oz), ivec3(csizex, osizey, osizez)};
		ChunkRange rx1y0z1 = {ivec3(cx,oy,cz), ivec3(csizex, osizey, csizez)};
		ChunkRange rx1y1z0 = {ivec3(cx,cy,oz), ivec3(csizex, csizey, osizez)};
		ChunkRange rx1y1z1 = {ivec3(cx,cy,cz), ivec3(csizex, csizey, csizez)};

		return [
		rx0y0z0, rx0y0z1, rx0y1z0, rx0y1z1,
		rx1y0z0, rx1y0z1, rx1y1z0, rx1y1z1];
	}
}

ChunkRange rangeIntersection(ChunkRange r1, ChunkRange r2)
{
	ChunkRange result;
	if (r1.coord.x < r2.coord.x)
	{
		if (r1.coord.x + r1.size.x < r2.coord.x) return ChunkRange();
		result.coord.x = r2.coord.x;
		result.size.x = r1.size.x - (r2.coord.x - r1.coord.x);
	}
	else
	{
		if (r2.coord.x + r2.size.x < r1.coord.x) return ChunkRange();
		result.coord.x = r1.coord.x;
		result.size.x = r2.size.x - (r1.coord.x - r2.coord.x);
	}

	if (r1.coord.y < r2.coord.y)
	{
		if (r1.coord.y + r1.size.y < r2.coord.y) return ChunkRange();
		result.coord.y = r2.coord.y;
		result.size.y = r1.size.y - (r2.coord.y - r1.coord.y);
	}
	else
	{
		if (r2.coord.y + r2.size.y < r1.coord.y) return ChunkRange();
		result.coord.y = r1.coord.y;
		result.size.y = r2.size.y - (r1.coord.y - r2.coord.y);
	}

	if (r1.coord.z < r2.coord.z)
	{
		if (r1.coord.z + r1.size.z < r2.coord.z) return ChunkRange();
		result.coord.z = r2.coord.z;
		result.size.z = r1.size.z - (r2.coord.z - r1.coord.z);
	}
	else
	{
		if (r2.coord.z + r2.size.z < r1.coord.z) return ChunkRange();
		result.coord.z = r1.coord.z;
		result.size.z = r2.size.z - (r1.coord.z - r2.coord.z);
	}

	result.size.x = result.size.x > 0 ? result.size.x : -result.size.x;
	result.size.y = result.size.y > 0 ? result.size.y : -result.size.y;
	result.size.z = result.size.z > 0 ? result.size.z : -result.size.z;

	return result;
}

unittest
{
	assert(rangeIntersection(
		ChunkRange(ivec3(0,0,0), ivec3(2,2,2)),
		ChunkRange(ivec3(1,1,1), ivec3(2,2,2))) ==
		ChunkRange(ivec3(1,1,1), ivec3(1,1,1)));
	assert(rangeIntersection(
		ChunkRange(ivec3(0,0,0), ivec3(2,2,2)),
		ChunkRange(ivec3(3,3,3), ivec3(4,4,4))) ==
		ChunkRange(ivec3()));
	assert(rangeIntersection(
		ChunkRange(ivec3(1,1,1), ivec3(2,2,2)),
		ChunkRange(ivec3(0,0,0), ivec3(2,2,2))) ==
		ChunkRange(ivec3(1,1,1), ivec3(1,1,1)));
	assert(rangeIntersection(
		ChunkRange(ivec3(1,1,1), ivec3(1,1,1)),
		ChunkRange(ivec3(1,1,1), ivec3(1,1,1))) ==
		ChunkRange(ivec3(1,1,1), ivec3(1,1,1)));
	assert(rangeIntersection(
		ChunkRange(ivec3(0,0,0), ivec3(2,2,2)),
		ChunkRange(ivec3(0,0,-1), ivec3(2,2,2))) ==
		ChunkRange(ivec3(0,0,0), ivec3(2,2,1)));
}

// Chunk data
struct ChunkData
{
	/// null if uniform is true, or contains chunk data otherwise
	BlockType[] typeData;
	/// type of common block
	BlockType uniformType = 0; // Unknown block
	/// is chunk filled with block of the same type
	bool uniform = true;

	BlockType getBlockType(ubyte cx, ubyte cy, ubyte cz)
	{
		if (uniform) return uniformType;
		return typeData[cx + cy * CHUNK_SIZE_SQR + cz * CHUNK_SIZE];
	}
}

// Single chunk
struct Chunk
{
	enum State
	{
		notLoaded, // needs loading
		isLoading, // do nothing while loading
		isMeshing, // do nothing while meshing
		ready,     // render
		//changed,   // needs meshing, render
	}

	@disable this();

	this(ivec3 coord)
	{
		this.coord = coord;
	}

	BlockType getBlockType(ubyte cx, ubyte cy, ubyte cz)
	{
		return data.getBlockType(cx, cy, cz);
	}

	bool areAllAdjacentLoaded() @property
	{
		foreach(a; adjacent)
		{
			if (a is null || !a.isLoaded) return false;
		}

		return true;
	}

	bool canBeMeshed() @property
	{
		return isLoaded && areAllAdjacentLoaded;
	}

	bool needsMesh() @property
	{
		return isLoaded && isVisible && !hasMesh && !isMeshing;
	}

	bool isUsed() @property
	{
		return numReaders > 0 || hasWriter;
	}

	bool isAnyAdjacentUsed() @property
	{
		foreach(a; adjacent)
			if (a !is null && a.isUsed) return true;
		return false;
	}

	bool isMarkedForDeletion() @property
	{
		return next || prev;
	}

	ivec3 coord;
	ChunkData data;
	ChunkMesh mesh;
	Chunk*[6] adjacent;

	bool isLoaded = false;
	bool isVisible = false;
	bool hasMesh = false;
	bool isMeshing = false;

	// How many tasks are reading or writing this chunk
	bool hasWriter = false;
	ushort numReaders = 0;

	// In deletion queue.
	Chunk* next;
	Chunk* prev;
}