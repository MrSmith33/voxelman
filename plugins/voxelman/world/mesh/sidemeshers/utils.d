/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.mesh.sidemeshers.utils;

import voxelman.math : ubvec3;
import voxelman.container.buffer : Buffer;
import voxelman.world.block.utils : MeshVertex2;
import voxelman.world.mesh.chunkmesh : MeshVertex;

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
	0.8, 0.85, 0.7, 0.75, 0.95, 0.65,
];

struct SideParams
{
	ubvec3 blockPos;
	ubvec3 color;
	ubyte rotation;
	Buffer!MeshVertex* buffer;
}

enum AO_VALUE_0 = 0.70f;
enum AO_VALUE_1 = 0.80f;
enum AO_VALUE_2 = 0.9f;
enum AO_VALUE_3 = 1.0f;

__gshared immutable(float[]) occlusionTable = [
	            // LT C
	AO_VALUE_3, // 00 0 case 3
	AO_VALUE_2, // 00 1 case 2
	AO_VALUE_2, // 01 0 case 2
	AO_VALUE_1, // 01 1 case 1
	AO_VALUE_2, // 10 0 case 2
	AO_VALUE_1, // 10 1 case 1
	AO_VALUE_0, // 11 0 case 0
	AO_VALUE_0, // 11 1 case 0
];

pragma(inline, true)
void meshOccludedQuad(T)(
	ref Buffer!MeshVertex buffer,
	ubyte[4] cornerOcclusion,
	const float[3] color,
	const ubvec3 offset,
	const ubyte[4] indices,
	const T[3]* vertieces)
{
	// Ambient occlusion multipliers
	float vert0AoMult = occlusionTable[cornerOcclusion[0]];
	float vert1AoMult = occlusionTable[cornerOcclusion[1]];
	float vert2AoMult = occlusionTable[cornerOcclusion[2]];
	float vert3AoMult = occlusionTable[cornerOcclusion[3]];

	immutable ubyte[3][4] finalColors = [
		[cast(ubyte)(vert0AoMult * color[0]), cast(ubyte)(vert0AoMult * color[1]), cast(ubyte)(vert0AoMult * color[2])],
		[cast(ubyte)(vert1AoMult * color[0]), cast(ubyte)(vert1AoMult * color[1]), cast(ubyte)(vert1AoMult * color[2])],
		[cast(ubyte)(vert2AoMult * color[0]), cast(ubyte)(vert2AoMult * color[1]), cast(ubyte)(vert2AoMult * color[2])],
		[cast(ubyte)(vert3AoMult * color[0]), cast(ubyte)(vert3AoMult * color[1]), cast(ubyte)(vert3AoMult * color[2])]];

	if(vert0AoMult + vert2AoMult > vert1AoMult + vert3AoMult)
	{
		meshColoredQuad!true(buffer, finalColors, offset, indices, vertieces);
	}
	else
	{
		meshColoredQuad!false(buffer, finalColors, offset, indices, vertieces);
	}
}

pragma(inline, true)
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
		cast(MeshVertex)MeshVertex2(
			vertieces[indices[ind.i0]][0] + offset.x,
			vertieces[indices[ind.i0]][1] + offset.y,
			vertieces[indices[ind.i0]][2] + offset.z,
			cornerColors[ind.i0]),
		cast(MeshVertex)MeshVertex2(
			vertieces[indices[ind.i1]][0] + offset.x,
			vertieces[indices[ind.i1]][1] + offset.y,
			vertieces[indices[ind.i1]][2] + offset.z,
			cornerColors[ind.i1]),
		cast(MeshVertex)MeshVertex2(
			vertieces[indices[ind.i2]][0] + offset.x,
			vertieces[indices[ind.i2]][1] + offset.y,
			vertieces[indices[ind.i2]][2] + offset.z,
			cornerColors[ind.i2]),
		cast(MeshVertex)MeshVertex2(
			vertieces[indices[ind.i3]][0] + offset.x,
			vertieces[indices[ind.i3]][1] + offset.y,
			vertieces[indices[ind.i3]][2] + offset.z,
			cornerColors[ind.i3]),
		cast(MeshVertex)MeshVertex2(
			vertieces[indices[ind.i4]][0] + offset.x,
			vertieces[indices[ind.i4]][1] + offset.y,
			vertieces[indices[ind.i4]][2] + offset.z,
			cornerColors[ind.i4]),
		cast(MeshVertex)MeshVertex2(
			vertieces[indices[ind.i5]][0] + offset.x,
			vertieces[indices[ind.i5]][1] + offset.y,
			vertieces[indices[ind.i5]][2] + offset.z,
			cornerColors[ind.i5])
	);
}
