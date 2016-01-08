/**
Copyright: Copyright (c) 2014-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.core.blockman;

import voxelman.core.block;
import voxelman.core.basicblocks;
import voxelman.storage.chunk;

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
			&sandBlock
		];
	}

	immutable(Block*)[] blocks()
	{
		return _blocks;
	}

	void onChunkLoaded(Chunk* chunk)
	{
		if (chunk.snapshot.blockData.uniform)
		{
			chunk.isVisible = blocks[chunk.snapshot.blockData.uniformType].isVisible;
		}
	}
}
