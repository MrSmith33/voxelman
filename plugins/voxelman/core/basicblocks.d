/**
Copyright: Copyright (c) 2014-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.core.basicblocks;

import voxelman.core.block;
import voxelman.core.config;


immutable Block unknownBlock = Block(0, "", [0,0,0], false,
			&sideIsNotTransparent, &makeNullMesh);
immutable Block airBlock = Block(1, "", [0,0,0], false,
			&sideIsTransparent, &makeNullMesh);
immutable Block grassBlock = makeColoredSolidBlock(2, [0, 255, 0]);
immutable Block dirtBlock = makeColoredSolidBlock(3, [120, 72, 0]);
immutable Block stoneBlock = makeColoredSolidBlock(4, [128, 128, 128]);
immutable Block sandBlock = makeColoredSolidBlock(5, [225, 169, 95]);


Block makeSolidBlock(BlockType id)
{
	return Block(id, "", [255, 255, 255], true,
		&sideIsNotTransparent,	&makeColoredBlockMesh);
}

Block makeColoredSolidBlock(BlockType id, ubyte[3] color)
{
	Block result = makeSolidBlock(id);
	result.color = color;
	return result;
}

bool sideIsNotTransparent(Side side){ return false; }
bool sideIsTransparent(Side side){ return true; }

ubyte[] makeNullMesh(const Block block,
	ubyte bx, ubyte by, ubyte bz, ubyte sides, ubyte sidesnum)
{
	return null;
}

ubyte[] makeColoredBlockMesh(const Block block,
		ubyte bx, ubyte by, ubyte bz, ubyte sides, ubyte sidesnum)
{
	import std.random;
	static immutable(float)[] shadowMultipliers = [
		0.7, 0.75, 0.6, 0.5, 0.85, 0.4,
	];
	ubyte[] data;
	data.reserve(sidesnum * 48);

	float randomTint = uniform(0.92f, 1.0f);

	foreach(ubyte i; 0..6)
	{
		if (sides & (2^^i))
		{
			for (size_t v = 0; v!=18; v+=3)
			{
				data ~= cast(ubyte)(faces[18*i+v] + bx);
				data ~= cast(ubyte)(faces[18*i+v+1] + by);
				data ~= cast(ubyte)(faces[18*i+v+2] + bz);
				data ~= 0;
				data ~= cast(ubyte)(shadowMultipliers[i] * block.color[0] * randomTint);
				data ~= cast(ubyte)(shadowMultipliers[i] * block.color[1] * randomTint);
				data ~= cast(ubyte)(shadowMultipliers[i] * block.color[2] * randomTint);
				data ~= 0;
			} // for v
		} // if
	} // for i

	return data;
}

// mesh for single block
immutable ubyte[18 * 6] faces =
[
	0, 0, 0, // triangle 1 : begin // north
	1, 0, 0,
	1, 1, 0, // triangle 1 : end
	0, 0, 0, // triangle 2 : begin
	1, 1, 0,
	0, 1, 0, // triangle 2 : end

	1, 0, 1, // south
	0, 0, 1,
	0, 1, 1,
	1, 0, 1,
	0, 1, 1,
	1, 1, 1,

	1, 0, 0, // east
	1, 0, 1,
	1, 1, 1,
	1, 0, 0,
	1, 1, 1,
	1, 1, 0,

	0, 0, 1, // west
	0, 0, 0,
	0, 1, 0,
	0, 0, 1,
	0, 1, 0,
	0, 1, 1,

	1, 1, 1, // top
	0, 1, 1,
	0, 1, 0,
	1, 1, 1,
	0, 1, 0,
	1, 1, 0,

	0, 0, 1, // bottom
	1, 0, 1,
	1, 0, 0,
	0, 0, 1,
	1, 0, 0,
	0, 0, 0,
];
