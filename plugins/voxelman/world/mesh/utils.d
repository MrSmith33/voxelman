/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.mesh.utils;

import voxelman.math;
import voxelman.geometry.cube;
import voxelman.core.config;
import voxelman.world.block;

enum EXTENDED_CHUNK_SIZE = CHUNK_SIZE + 2;
enum EXTENDED_CHUNK_SIZE_SQR = EXTENDED_CHUNK_SIZE * EXTENDED_CHUNK_SIZE;
enum EXTENDED_CHUNK_SIZE_CUBE = EXTENDED_CHUNK_SIZE * EXTENDED_CHUNK_SIZE * EXTENDED_CHUNK_SIZE;
enum EXTENDED_SIZE_VECTOR = ivec3(EXTENDED_CHUNK_SIZE, EXTENDED_CHUNK_SIZE, EXTENDED_CHUNK_SIZE);

size_t extendedChunkIndex(int x, int y, int z) {
	return x + y * EXTENDED_CHUNK_SIZE_SQR + z * EXTENDED_CHUNK_SIZE;
}

size_t chunkFromExtIndex(size_t index)
{
	int x = index % EXTENDED_CHUNK_SIZE;
	int y = (index / EXTENDED_CHUNK_SIZE_SQR) % EXTENDED_CHUNK_SIZE;
	int z = (index / EXTENDED_CHUNK_SIZE) % EXTENDED_CHUNK_SIZE;

	ubyte cx = target_chunk[x];
	ubyte cy = target_chunk[y];
	ubyte cz = target_chunk[z];

	return dirs3by3[cx + cz * 3 + cy * 9];
}

ChunkAndBlockAt chunkAndBlockAt27FromExt(ushort index)
{
	int x = index % EXTENDED_CHUNK_SIZE;
	int y = (index / EXTENDED_CHUNK_SIZE_SQR) % EXTENDED_CHUNK_SIZE;
	int z = (index / EXTENDED_CHUNK_SIZE) % EXTENDED_CHUNK_SIZE;

	ubyte bx = position_in_target_chunk[x];
	ubyte by = position_in_target_chunk[y];
	ubyte bz = position_in_target_chunk[z];

	ubyte cx = target_chunk[x];
	ubyte cy = target_chunk[y];
	ubyte cz = target_chunk[z];

	ubyte chunk_index = dirs3by3[cx + cz * 3 + cy * 9];

	return ChunkAndBlockAt(chunk_index, bx, by, bz);
}

import voxelman.world.storage.arraycopy;
import voxelman.geometry.box;

immutable short[6] sideIndexOffsets = [
	-EXTENDED_CHUNK_SIZE, // zneg
	 EXTENDED_CHUNK_SIZE, // zpos
	 1, // xpos
	-1, // xneg
	 EXTENDED_CHUNK_SIZE_SQR, // ypos
	-EXTENDED_CHUNK_SIZE_SQR, // yneg
];
private alias sio = sideIndexOffsets;

immutable short[27] sideIndexOffsets27 = [
	// 6 adjacent
	sio[CubeSide.zneg], // zneg
	sio[CubeSide.zpos], // zpos
	sio[CubeSide.xpos], // xpos
	sio[CubeSide.xneg], // xneg
	sio[CubeSide.ypos], // ypos
	sio[CubeSide.yneg], // yneg

	// bottom 8
	sio[CubeSide.xneg] + sio[CubeSide.yneg] + sio[CubeSide.zneg], // xneg_yneg_zneg
	                     sio[CubeSide.yneg] + sio[CubeSide.zneg], //      yneg_zneg
	sio[CubeSide.xpos] + sio[CubeSide.yneg] + sio[CubeSide.zneg], // xpos_yneg_zneg
	sio[CubeSide.xneg] + sio[CubeSide.yneg]                     , // xneg_yneg
	sio[CubeSide.xpos] + sio[CubeSide.yneg]                     , // xpos_yneg
	sio[CubeSide.xneg] + sio[CubeSide.yneg] + sio[CubeSide.zpos], // xneg_yneg_zpos
	                     sio[CubeSide.yneg] + sio[CubeSide.zpos], //      yneg_zpos
	sio[CubeSide.xpos] + sio[CubeSide.yneg] + sio[CubeSide.zpos], // xpos_yneg_zpos

	// middle 4
	sio[CubeSide.xneg] + sio[CubeSide.zneg], // xneg_zneg [-1, 0,-1]
	sio[CubeSide.xpos] + sio[CubeSide.zneg], // xpos_zneg [ 1, 0,-1]
	sio[CubeSide.xneg] + sio[CubeSide.zpos], // xneg_zpos [-1, 0, 1]
	sio[CubeSide.xpos] + sio[CubeSide.zpos], // xpos_zpos [ 1, 0, 1]

	// top 8
	sio[CubeSide.xneg] + sio[CubeSide.ypos] + sio[CubeSide.zneg], // xneg_ypos_zneg [-1, 1,-1]
	                     sio[CubeSide.ypos] + sio[CubeSide.zneg], //      ypos_zneg [ 0, 1,-1]
	sio[CubeSide.xpos] + sio[CubeSide.ypos] + sio[CubeSide.zneg], // xpos_ypos_zneg [ 1, 1,-1]
	sio[CubeSide.xneg] + sio[CubeSide.ypos]                     , // xneg_ypos      [-1, 1, 0]
	sio[CubeSide.xpos] + sio[CubeSide.ypos]                     , // xpos_ypos      [ 1, 1, 0]
	sio[CubeSide.xneg] + sio[CubeSide.ypos] + sio[CubeSide.zpos], // xneg_ypos_zpos [-1, 1, 1]
	                     sio[CubeSide.ypos] + sio[CubeSide.zpos], //      ypos_zpos [ 0, 1, 1]
	sio[CubeSide.xpos] + sio[CubeSide.ypos] + sio[CubeSide.zpos], // xpos_ypos_zpos [ 1, 1, 1]

	0 // central
];
private alias sio27 = sideIndexOffsets27;

// on sides top points in ypos dir
enum FaceSide : ubyte {
	top, // zneg dir on horizontal faces (top and bottom)
	left,
	bottom,
	right
}

// for each cube side
//   8 index offsets
//   first four are offsets to 4 adjacent sides, next 4 are for corner
// 4 0 7
// 1   3
// 5 2 6
static immutable short[8][6] faceSideIndexOffset = [
	/*0-3*/ [sio27[Dir27.ypos], sio27[Dir27.xpos], sio27[Dir27.yneg], sio27[Dir27.xneg], /*4-7*/ sio27[Dir27.xpos_ypos], sio27[Dir27.xpos_yneg], sio27[Dir27.xneg_yneg], sio27[Dir27.xneg_ypos]], // zneg
	/*0-3*/ [sio27[Dir27.ypos], sio27[Dir27.xneg], sio27[Dir27.yneg], sio27[Dir27.xpos], /*4-7*/ sio27[Dir27.xneg_ypos], sio27[Dir27.xneg_yneg], sio27[Dir27.xpos_yneg], sio27[Dir27.xpos_ypos]], // zpos
	/*0-3*/ [sio27[Dir27.ypos], sio27[Dir27.zpos], sio27[Dir27.yneg], sio27[Dir27.zneg], /*4-7*/ sio27[Dir27.ypos_zpos], sio27[Dir27.yneg_zpos], sio27[Dir27.yneg_zneg], sio27[Dir27.ypos_zneg]], // xpos
	/*0-3*/ [sio27[Dir27.ypos], sio27[Dir27.zneg], sio27[Dir27.yneg], sio27[Dir27.zpos], /*4-7*/ sio27[Dir27.ypos_zneg], sio27[Dir27.yneg_zneg], sio27[Dir27.yneg_zpos], sio27[Dir27.ypos_zpos]], // xneg

	/*0-3*/ [sio27[Dir27.zneg], sio27[Dir27.xneg], sio27[Dir27.zpos], sio27[Dir27.xpos], /*4-7*/ sio27[Dir27.xneg_zneg], sio27[Dir27.xneg_zpos], sio27[Dir27.xpos_zpos], sio27[Dir27.xpos_zneg]], // ypos
	/*0-3*/ [sio27[Dir27.zneg], sio27[Dir27.xpos], sio27[Dir27.zpos], sio27[Dir27.xneg], /*4-7*/ sio27[Dir27.xpos_zneg], sio27[Dir27.xpos_zpos], sio27[Dir27.xneg_zpos], sio27[Dir27.xneg_zneg]], // yneg
];

// maps block side to map of 12 corner ids. 3 corners of adjacent cubes for each face corner.
// each corner is a corner of cube adjacent to given face (one of 6 sides). Those cube corners will affect AO of face corners.
// 1 | 0  11 | 10
// --+-------+----
// 2 |*     *|  9
//   |       |
// 3 |*     *|  8
// --+-------+----
// 4 | 5   6 |  7
// those correspond to 4 face corners (marked as * above)
// 0--3 // corner numbering of face verticies
// |  |
// 1--2
// where cube corners are from CubeCorner

static immutable ubyte[12][6] faceSideCorners = [
	[3, 2, 6,  2, 6, 7,  6, 7, 3,  7, 3, 2], // zneg
	[0, 1, 5,  1, 5, 4,  5, 4, 0,  4, 0, 1], // zpos
	[2, 0, 4,  0, 4, 6,  4, 6, 2,  6, 2, 0], // xpos
	[1, 3, 7,  3, 7, 5,  7, 5, 1,  5, 1, 3], // xneg
	[2, 3, 1,  3, 1, 0,  1, 0, 2,  0, 2, 3], // ypos
	[7, 6, 4,  6, 4, 5,  4, 5, 7,  5, 7, 6], // yneg
];

// maps block side to map of 12 corner ids. 3 corners of adjacent cubes for each face corner.
// each corner is a corner of cube adjacent to given face (one of 6 sides). Those cube corners will affect AO of face corners.
// 2 | 1  15 | 14
// --+-------+----
// 3 | 0  12 | 13
//   |       |
// 5 | 4   8 | 11
// --+-------+----
// 6 | 7   9 | 10
// those correspond to 4 face corners (marked as * above)
// 0--3 // corner numbering of face verticies
// |  |
// 1--2
// where cube corners are from CubeCorner

static immutable ubyte[16][6] faceSideCorners4 = [
	[7,3,2,6, 3,2,6,7, 2,6,7,3, 6,7,3,2], // zneg
	[4,0,1,5, 0,1,5,4, 1,5,4,0, 5,4,0,1], // zpos
	[6,2,0,4, 2,0,4,6, 0,4,6,2, 1,6,2,0], // xpos
	[5,1,3,7, 1,3,7,5, 3,7,5,1, 7,5,1,3], // xneg
	[0,2,3,1, 2,3,1,0, 3,1,0,2, 1,0,2,3], // ypos
	[5,7,6,4, 7,6,4,5, 6,4,5,7, 4,5,7,6], // yneg
];
