/**
Copyright: Copyright (c) 2013-2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.block;


alias BlockType = ubyte;

abstract class IBlock
{
	pure this(BlockType id)
	{
		this.id = id;
	}
	// TODO remake as table
	//Must return true if the side allows light to pass
	bool isSideTransparent(ubyte side);

	bool isVisible();
	
	//Must return mesh for block in given position for given sides
	//sides is contains [6] bit flags of wich side must be builded
	ubyte[] getMesh(ubyte bx, ubyte by, ubyte bz, ubyte sides, ubyte sidesnum);
	
	float texX1, texY1, texX2, texY2;
	BlockType id;
}

class SolidBlock : IBlock
{
	pure this(BlockType id){super(id);}

	override bool isSideTransparent(ubyte side) {return false;}

	override bool isVisible() {return true;}

	immutable(float)[] colors =
	[
		0.7, 0.75, 0.6, 0.5, 0.85, 0.4,
	];

	ubyte r = 1, g = 1, b = 1;

	override ubyte[] getMesh(ubyte bx, ubyte by, ubyte bz, ubyte sides, ubyte sidesnum)
	{
		ubyte[] data;
		data.reserve(sidesnum*48);

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
					data ~= cast(ubyte)(colors[i] * r);
					data ~= cast(ubyte)(colors[i] * g);
					data ~= cast(ubyte)(colors[i] * b);
					data ~= 0;
				} // for v
			} // if
		} // for i

		return data;
	}
}

class GrassBlock : SolidBlock
{
	pure this(BlockType id)
	{
		super(id);
		r = 0;
		g = 255;
		b = 0;
	}
}

class DirtBlock : SolidBlock
{
	pure this(BlockType id)
	{
		super(id);
		r = 120;
		g = 72;
		b = 0;
	}
}

class StoneBlock : SolidBlock
{
	pure this(BlockType id)
	{
		super(id);
		r = 128;
		g = 128;
		b = 128;
	}
}

class UnknownBlock : IBlock
{
	this(BlockType id){super(id);}

	override bool isSideTransparent(ubyte side) {return false;}

	override bool isVisible() {return false;}

	override ubyte[] getMesh(ubyte bx, ubyte by, ubyte bz, ubyte sides, ubyte sidesnum)
	{
		return null;
	}
}

class AirBlock : IBlock
{
	this(BlockType id){super(id);}

	override bool isSideTransparent(ubyte side) {return true;}

	override bool isVisible() {return false;}

	override ubyte[] getMesh(ubyte bx, ubyte by, ubyte bz, ubyte sides, ubyte sidesnum)
	{
		return null;
	}
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

enum Side : ubyte
{
	north	= 0,
	south	= 1,
	
	east	= 2,
	west	= 3,
	
	top		= 4,
	bottom	= 5,
}

immutable ubyte[6] oppSide =
[1, 0, 3, 2, 5, 4];

immutable byte[3][6] sideOffsets =
[
	[ 0, 0,-1],
	[ 0, 0, 1],
	[ 1, 0, 0],
	[-1, 0, 0],
	[ 0, 1, 0],
	[ 0,-1, 0],
];