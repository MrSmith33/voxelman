/**
Copyright: Copyright (c) 2013-2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.chunk;

import std.string : format;

import dlib.math.vector;

import voxelman.block;
import voxelman.chunkmesh;


enum chunkSize = 32;
enum chunkSizeBits = chunkSize - 1;
enum chunkSizeSqr = chunkSize * chunkSize;
enum chunkSizeCube = chunkSize * chunkSize * chunkSize;

alias Vector!(short, 4) svec4;

// chunk position in chunk coordinate space
struct ChunkCoord
{
	union
	{
		struct
		{
			short x, y, z;
			short _;
		}
		svec4 vector;
		ulong asLong;
	}

	alias vector this;

	string toString()
	{
		return format("{%s %s %s}", x, y, z);
	}

	bool opEquals(ChunkCoord other)
	{
		return asLong == other.asLong;
	}

	size_t manhattanDist(ChunkCoord other)
	{
		return other.x > x ? other.x - x : x - other.x +
				other.y > y ? other.y - y : y - other.y +
				other.z > z ? other.z - z : z - other.z;
	}

	double euclidDist(ChunkCoord other)
	{
		import std.math : sqrt;
		return sqrt(cast(real)(other.x > x ? other.x - x : x - other.x)^^2 +
				(other.y > y ? other.y - y : y - other.y)^^2 +
				(other.z > z ? other.z - z : z - other.z)^^2);
	}
}

// 3d slice of chunks
struct ChunkRange
{
	ChunkCoord coord;
	ivec3 size;

	int volume()
	{
		return size.x * size.y * size.z;
	}

	bool contains(ChunkCoord otherCoord)
	{
		if (otherCoord.x < coord.x || otherCoord.x >= coord.x + size.x) return false;
		if (otherCoord.y < coord.y || otherCoord.y >= coord.y + size.y) return false;
		if (otherCoord.z < coord.z || otherCoord.z >= coord.z + size.z) return false;
		return true;
	}

	import std.algorithm : cartesianProduct, map, joiner, equal, canFind;
	import std.range : iota, walkLength;
	import std.array : array;

	// generates all chunk coordinates that are contained inside chunk range.
	auto chunkCoords()
	{
		return cartesianProduct(
			iota(coord.x, cast(short)(coord.x+size.x)),
			iota(coord.y, cast(short)(coord.y+size.y)),
			iota(coord.z, cast(short)(coord.z+size.z)))
			.map!((a)=>ChunkCoord(a[0], a[1], a[2]));
	}

	unittest
	{
		assert(ChunkRange(ChunkCoord(0,0,0), ivec3(3,3,3)).chunkCoords.walkLength == 27);
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
		ChunkRange cr = {{0,0,0}, ivec3(2,2,2)};
		ChunkRange other1 = {{1,1,1}, ivec3(2,2,2)}; // opposite intersection {1,1,1}
		ChunkRange other2 = {{2,2,2}, ivec3(2,2,2)}; // no intersection
		ChunkRange other3 = {{0,0,1}, ivec3(2,2,2)}; // half intersection
		ChunkRange other4 = {{0,0,-1}, ivec3(2,2,2)}; // half intersection

		ChunkRange half1 = {{0,0,0}, ivec3(2,2,1)};
		ChunkRange half2 = {{0,0,1}, ivec3(2,2,1)};

		assert( !cr.chunksNotIn(other1).canFind(ChunkCoord(1,1,1)) );
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
		short cx, cy, cz;

		if (corner.coord.x == coord.x) // x0
			cx = cast(short)(corner.coord.x + corner.size.x);
		else // x1
			cx = corner.coord.x;

		if (corner.coord.y == coord.y) // y0
			cy = cast(short)(corner.coord.y + corner.size.y);
		else // y1
			cy = corner.coord.y;

		if (corner.coord.z == coord.z) // z0
			cz = cast(short)(corner.coord.z + corner.size.z);
		else // z1
			cz = corner.coord.z;


		// origin coordinates
		short ox = coord.x, oy = coord.y, oz = coord.z;
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


		alias CC = ChunkCoord;
		ChunkRange rx0y0z0 = {CC(ox,oy,oz), ivec3(osizex, osizey, osizez)};
		ChunkRange rx0y0z1 = {CC(ox,oy,cz), ivec3(osizex, osizey, csizez)};
		ChunkRange rx0y1z0 = {CC(ox,cy,oz), ivec3(osizex, csizey, osizez)};
		ChunkRange rx0y1z1 = {CC(ox,cy,cz), ivec3(osizex, csizey, csizez)};

		ChunkRange rx1y0z0 = {CC(cx,oy,oz), ivec3(csizex, osizey, osizez)};
		ChunkRange rx1y0z1 = {CC(cx,oy,cz), ivec3(csizex, osizey, csizez)};
		ChunkRange rx1y1z0 = {CC(cx,cy,oz), ivec3(csizex, csizey, osizez)};
		ChunkRange rx1y1z1 = {CC(cx,cy,cz), ivec3(csizex, csizey, csizez)};

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
		ChunkRange(ChunkCoord(0,0,0), ivec3(2,2,2)),
		ChunkRange(ChunkCoord(1,1,1), ivec3(2,2,2))) ==
		ChunkRange(ChunkCoord(1,1,1), ivec3(1,1,1)));
	assert(rangeIntersection(
		ChunkRange(ChunkCoord(0,0,0), ivec3(2,2,2)),
		ChunkRange(ChunkCoord(3,3,3), ivec3(4,4,4))) ==
		ChunkRange(ChunkCoord()));
	assert(rangeIntersection(
		ChunkRange(ChunkCoord(1,1,1), ivec3(2,2,2)),
		ChunkRange(ChunkCoord(0,0,0), ivec3(2,2,2))) ==
		ChunkRange(ChunkCoord(1,1,1), ivec3(1,1,1)));
	assert(rangeIntersection(
		ChunkRange(ChunkCoord(1,1,1), ivec3(1,1,1)),
		ChunkRange(ChunkCoord(1,1,1), ivec3(1,1,1))) ==
		ChunkRange(ChunkCoord(1,1,1), ivec3(1,1,1)));
	assert(rangeIntersection(
		ChunkRange(ChunkCoord(0,0,0), ivec3(2,2,2)),
		ChunkRange(ChunkCoord(0,0,-1), ivec3(2,2,2))) ==
		ChunkRange(ChunkCoord(0,0,0), ivec3(2,2,1)));
}

// Chunk data
struct ChunkData
{
	/// null if homogeneous is true, or contains chunk data otherwise
	BlockType[] typeData;
	/// type of common block
	BlockType uniformType = 0; // Unknown block
	/// is chunk filled with block of the same type
	bool uniform = true;
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

	this(ChunkCoord coord)
	{
		this.coord = coord;
		//mesh = new ChunkMesh();
	}

	BlockType getBlockType(ubyte cx, ubyte cy, ubyte cz)
	{
		if (data.uniform) return data.uniformType;
		return data.typeData[cx + cy*chunkSizeSqr + cz*chunkSize];
	}

	bool areAllAdjacentLoaded() @property
	{
		foreach(a; adjacent)
		{
			if (!a.isLoaded) return false;
		}

		return true;
	}

	bool canBeMeshed() @property
	{
		return isLoaded && areAllAdjacentLoaded();
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
			if (a != Chunk.unknownChunk && a.isUsed) return true;
		return false;
	}

	bool isMarkedForDeletion() @property
	{
		return next || prev;
	}

	ChunkData data;
	ChunkMesh mesh;
	ChunkCoord coord;
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

	// Null chunk.
	static Chunk* unknownChunk;
	static Chunk* initChunk; // To compare with unknownChunk. If differs, there is an error in the code.
}

static this()
{
	Chunk.unknownChunk = new Chunk(ChunkCoord(0, 0, 0));
	Chunk.initChunk = new Chunk(ChunkCoord(0, 0, 0));
}