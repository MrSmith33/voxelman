/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.mesh.sidemeshers.utils;

import voxelman.math : ubvec3;
import voxelman.container.buffer : Buffer;
import voxelman.world.mesh.vertex : MeshVertex;
import voxelman.world.mesh.config;

float random(uint num) pure nothrow
{
	uint x = num;
	x = ((x >> 16) ^ x) * 0x45d9f3b;
	x = ((x >> 16) ^ x) * 0x45d9f3b;
	x = (x >> 16) ^ x;
	return (cast(float)x / uint.max);
}

float calcRandomTint(ushort index) pure nothrow
{
	return random(index)*0.1+0.9;
}

ubvec3 calcColor(ushort index, ubvec3 color) pure nothrow
{
	float randomTint = calcRandomTint(index);
	return ubvec3(
		color.r * randomTint,
		color.g * randomTint,
		color.b * randomTint);
}

immutable(float[]) shadowMultipliers = [
	0.85, 0.9, 0.75, 0.8, 1, 0.7,
];

struct SideParams
{
	ubvec3 blockPos;
	ubvec3 color;
	ubyte[2] uv;
	ubyte rotation;
	Buffer!MeshVertex* buffer;
}

enum AO_VALUE_0 = 0.70f;
enum AO_VALUE_1 = 0.80f;
enum AO_VALUE_2 = 0.9f;
enum AO_VALUE_3 = 1.0f;

__gshared immutable(float[]) occlusionTable = [
	            // * C LT - center, corner, left, top
	AO_VALUE_3, //   0 00 case 3
	AO_VALUE_2, //   0 01 case 2
	AO_VALUE_2, //   0 10 case 2
	AO_VALUE_0, //   0 11 case 0
	AO_VALUE_2, //   1 00 case 2
	AO_VALUE_1, //   1 01 case 1
	AO_VALUE_1, //   1 10 case 1
	AO_VALUE_0, //   1 11 case 0

	AO_VALUE_2, // 1 0 00
	AO_VALUE_1, // 1 0 01
	AO_VALUE_1, // 1 0 10
	AO_VALUE_0, // 1 0 11
	AO_VALUE_0, // 1 1 00
	AO_VALUE_1, // 1 1 01
	AO_VALUE_1, // 1 1 10
	AO_VALUE_0, // 1 1 11
];

enum AO_COLOR_0 = Colors.violet;
enum AO_COLOR_1 = Colors.red;
enum AO_COLOR_2 = Colors.orange;
enum AO_COLOR_3 = Colors.white;

import voxelman.graphics.color;
Color4ub[] aoDebugColors = [
	            // * C LT - center, corner, left, top
	AO_COLOR_3, //   0 00 case 3
	AO_COLOR_2, //   0 01 case 2
	AO_COLOR_2, //   0 10 case 2
	AO_COLOR_0, //   0 11 case 0
	AO_COLOR_2, //   1 00 case 2
	AO_COLOR_1, //   1 01 case 1
	AO_COLOR_1, //   1 10 case 1
	AO_COLOR_0, //   1 11 case 0

	AO_COLOR_2, // 1 0 00
	AO_COLOR_1, // 1 0 01
	AO_COLOR_1, // 1 0 10
	AO_COLOR_0, // 1 0 11
	AO_COLOR_0, // 1 1 00
	AO_COLOR_1, // 1 1 01
	AO_COLOR_1, // 1 1 10
	AO_COLOR_0, // 1 1 11
];

ubyte[3][4] getDebugAOColors(ubyte[4] cornerOcclusion)
{
	return [
		aoDebugColors[cornerOcclusion[0]].rgb.arrayof,
		aoDebugColors[cornerOcclusion[1]].rgb.arrayof,
		aoDebugColors[cornerOcclusion[2]].rgb.arrayof,
		aoDebugColors[cornerOcclusion[3]].rgb.arrayof,
	];
}

//pragma(inline, true)
void meshOccludedQuad(T)(
	ref Buffer!MeshVertex buffer,
	ubyte[4] cornerOcclusion,
	const float[3] color,
	ubyte[2] uv,
	const ubvec3 offset,
	const ubyte[4] indices,
	const T[3]* vertieces)
{
	// Ambient occlusion multipliers
	ubyte vert0AoMult = cast(ubyte)(255 * occlusionTable[cornerOcclusion[0]]);
	ubyte vert1AoMult = cast(ubyte)(255 * occlusionTable[cornerOcclusion[1]]);
	ubyte vert2AoMult = cast(ubyte)(255 * occlusionTable[cornerOcclusion[2]]);
	ubyte vert3AoMult = cast(ubyte)(255 * occlusionTable[cornerOcclusion[3]]);

	//static if (AO_DEBUG_ENABLED)
	//	immutable ubyte[3][4] finalColors = getDebugAOColors(cornerOcclusion);
	//else
	//	immutable ubyte[3][4] finalColors = [
	//		[cast(ubyte)(vert0AoMult * color[0]), cast(ubyte)(vert0AoMult * color[1]), cast(ubyte)(vert0AoMult * color[2])],
	//		[cast(ubyte)(vert1AoMult * color[0]), cast(ubyte)(vert1AoMult * color[1]), cast(ubyte)(vert1AoMult * color[2])],
	//		[cast(ubyte)(vert2AoMult * color[0]), cast(ubyte)(vert2AoMult * color[1]), cast(ubyte)(vert2AoMult * color[2])],
	//		[cast(ubyte)(vert3AoMult * color[0]), cast(ubyte)(vert3AoMult * color[1]), cast(ubyte)(vert3AoMult * color[2])]];
	immutable ubyte[4] finalColors = [vert0AoMult, vert1AoMult, vert2AoMult, vert3AoMult];
	immutable ubyte[2][4] uvs = [uv, [uv[0], cast(ubyte)(uv[1]+1)], [cast(ubyte)(uv[0]+1), cast(ubyte)(uv[1]+1)], [cast(ubyte)(uv[0]+1), uv[1]]];

	if(vert0AoMult + vert2AoMult > vert1AoMult + vert3AoMult)
	{
		meshQuadUvGray!true(buffer, finalColors, uvs, offset, indices, vertieces);
	}
	else
	{
		meshQuadUvGray!false(buffer, finalColors, uvs, offset, indices, vertieces);
	}
}

//pragma(inline, true)
void meshColoredQuad(bool flipped, T)(
	ref Buffer!MeshVertex buffer,
	ref const ubyte[3][4] cornerColors,
	const ubvec3 offset,
	const ubyte[4] indices,
	const T[3]* vertieces)
{
	// index order
	static if (flipped)
		enum ind {i0=1, i1=2, i2=0, i3=0, i4=2, i5=3}
	else
		enum ind {i0=1, i1=3, i2=0, i3=1, i4=2, i5=3}

	buffer.put(
		MeshVertex(
			vertieces[indices[ind.i0]][0] + offset.x,
			vertieces[indices[ind.i0]][1] + offset.y,
			vertieces[indices[ind.i0]][2] + offset.z,
			cornerColors[ind.i0]),
		MeshVertex(
			vertieces[indices[ind.i1]][0] + offset.x,
			vertieces[indices[ind.i1]][1] + offset.y,
			vertieces[indices[ind.i1]][2] + offset.z,
			cornerColors[ind.i1]),
		MeshVertex(
			vertieces[indices[ind.i2]][0] + offset.x,
			vertieces[indices[ind.i2]][1] + offset.y,
			vertieces[indices[ind.i2]][2] + offset.z,
			cornerColors[ind.i2]),
		MeshVertex(
			vertieces[indices[ind.i3]][0] + offset.x,
			vertieces[indices[ind.i3]][1] + offset.y,
			vertieces[indices[ind.i3]][2] + offset.z,
			cornerColors[ind.i3]),
		MeshVertex(
			vertieces[indices[ind.i4]][0] + offset.x,
			vertieces[indices[ind.i4]][1] + offset.y,
			vertieces[indices[ind.i4]][2] + offset.z,
			cornerColors[ind.i4]),
		MeshVertex(
			vertieces[indices[ind.i5]][0] + offset.x,
			vertieces[indices[ind.i5]][1] + offset.y,
			vertieces[indices[ind.i5]][2] + offset.z,
			cornerColors[ind.i5])
	);
}

void meshQuadUvGray(bool flipped, T)(
	ref Buffer!MeshVertex buffer,
	ref const ubyte[4] cornerColors,
	ref const ubyte[2][4] cornerUVs,
	const ubvec3 offset,
	const ubyte[4] indices,
	const T[3]* vertieces)
{
	// index order
	static if (flipped)
		enum ind {i0=1, i1=2, i2=0, i3=0, i4=2, i5=3}
	else
		enum ind {i0=1, i1=3, i2=0, i3=1, i4=2, i5=3}

	buffer.put(
		MeshVertex(
			vertieces[indices[ind.i0]][0] + offset.x,
			vertieces[indices[ind.i0]][1] + offset.y,
			vertieces[indices[ind.i0]][2] + offset.z,
			cornerUVs[ind.i0],
			cornerColors[ind.i0]),
		MeshVertex(
			vertieces[indices[ind.i1]][0] + offset.x,
			vertieces[indices[ind.i1]][1] + offset.y,
			vertieces[indices[ind.i1]][2] + offset.z,
			cornerUVs[ind.i1],
			cornerColors[ind.i1]),
		MeshVertex(
			vertieces[indices[ind.i2]][0] + offset.x,
			vertieces[indices[ind.i2]][1] + offset.y,
			vertieces[indices[ind.i2]][2] + offset.z,
			cornerUVs[ind.i2],
			cornerColors[ind.i2]),
		MeshVertex(
			vertieces[indices[ind.i3]][0] + offset.x,
			vertieces[indices[ind.i3]][1] + offset.y,
			vertieces[indices[ind.i3]][2] + offset.z,
			cornerUVs[ind.i3],
			cornerColors[ind.i3]),
		MeshVertex(
			vertieces[indices[ind.i4]][0] + offset.x,
			vertieces[indices[ind.i4]][1] + offset.y,
			vertieces[indices[ind.i4]][2] + offset.z,
			cornerUVs[ind.i4],
			cornerColors[ind.i4]),
		MeshVertex(
			vertieces[indices[ind.i5]][0] + offset.x,
			vertieces[indices[ind.i5]][1] + offset.y,
			vertieces[indices[ind.i5]][2] + offset.z,
			cornerUVs[ind.i5],
			cornerColors[ind.i5])
	);
}
