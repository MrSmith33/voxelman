/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.blockman;

import voxelman.block;
import voxelman.basicblocks;

struct BlockMan
{
	private immutable(Block*)[] _blocks;

	void loadBlockTypes()
	{
		_blocks = [
			&unknownBlock,
			&airBlock,
			&grassBlock,
			&dirtBlock,
			&stoneBlock,
		];
	}

	immutable(Block*)[] blocks()
	{
		return _blocks;
	}
}